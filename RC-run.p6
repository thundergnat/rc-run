use HTTP::UserAgent;
use URI::Escape;
use JSON::Fast;
use Text::Levenshtein::Damerau;
use MONKEY-SEE-NO-EVAL;

#####################################
say "Version = 2020-02-17T01:09:41";
#####################################

sleep 1;

my %*SUB-MAIN-OPTS = :named-anywhere;

unit sub MAIN(
    Str $run = '',        #= Task or file name
    Str :$lang = 'perl6', #= Language, default perl6 - should be same as in <lang *> markup
    Int :$skip = 0,       #= Skip # to continue partially into a list
    Bool :f(:$force),     #= Override any task skip parameter in %resource hash
    Bool :l(:$local),     #= Only use code from local cache
    Bool :r(:$remote),    #= Only use code from remote server (refresh local cache)
    Bool :q(:$quiet),     #= Less verbose, don't display source code
    Bool :d(:$deps),      #= Load dependencies
    Bool :p(:$pause),     #= pause after each task
    Bool :b(:$broken),    #= pause after each task which is broken or fails in some way
    Int  :$sleep = 0,     #= sleep for $sleep after each task
    Bool :t(:$timer),     #= save timing data for each task
);

die 'You can select local or remote, but not both...' if $local && $remote;

## INITIALIZATION

my $client   = HTTP::UserAgent.new;
my $url      = 'http://rosettacode.org/mw';

my %c = ( # text colors
    code  => "\e[0;92m", # green
    delim => "\e[0;93m", # yellow
    cmd   => "\e[1;96m", # cyan
    bad   => "\e[0;91m", # red
    warn  => "\e[38;2;255;155;0m", # orange
    dep   => "\e[38;2;248;24;148m", # pink
    clr   => "\e[0m",    # clear formatting
);

my $view      = 'xdg-open';       # image viewer, this will open default under Linux
my %l         = load-lang($lang); # load language parameters
my %resource  = load-resources($lang);
my $get-tasks = True;

my @tasks;

run('clear');

## FIGURE OUT WHICH TASKS TO RUN

if $run {
    if $run.IO.e and $run.IO.f {# is it a file?
        @tasks = $run.IO.lines; # yep, treat each line as a task name
    } else {                    # must be a single task name
        @tasks = ($run);        # treat it so
    }
    $get-tasks = False;         # don't need to retrieve task names from web
}

if $get-tasks { # load tasks from web if cache is not found, older than one day or forced
    if !"%l<dir>.tasks".IO.e or (now - "%l<dir>.tasks".IO.modified) > 86400 or $remote {
        note 'Retrieving task list from site.';
        @tasks = mediawiki-query( # get tasks from web
        $url, 'pages',
        :generator<categorymembers>,
        :gcmtitle("Category:%l<language>"),
        :gcmlimit<350>,
        :rawcontinue(),
        :prop<title>
        )»<title>.grep( * !~~ /^'Category:'/ ).sort;
        "%l<dir>.tasks".IO.spurt: @tasks.sort.join("\n");
    } else {
        note 'Using cached task list.';
        @tasks = "%l<dir>.tasks".IO.slurp.lines; # load tasks from file
    }
}

my $tfile;
if $timer {
    $tfile = open :w, "{$lang}-time.txt";
    $tfile.close;
}

note "Skipping first $skip tasks..." if $skip;
my $redo;

## MAIN LOOP

for @tasks -> $title {
    $redo = False;
    next if $++ < $skip;
    next unless $title ~~ /\S/; # filter blank lines (from files)
    say my $tasknum = $skip + ++$, ")  $title";

    my $name = $title.subst(/<-[-0..9A..Za..z]>/, '_', :g);
    my $taskdir = "./rc/%l<dir>/$name";

    my $modified = "$taskdir/$name.txt".IO.e ?? "$taskdir/$name.txt".IO.modified !! 0;

    my $entry;
    if $remote or !"$taskdir/$name.txt".IO.e or ((now - $modified) > 86400 * 7) {
        my $page = $client.get("{ $url }/index.php?title={ uri-escape $title }&action=raw").content;

        uh-oh("Whoops, can't find page: $url/$title :check spelling.\n\n{fuzzy-search($title)}", 'warn')
            and next if $page.elems == 0;
        say "Getting code from: http://rosettacode.org/wiki/{ $title.subst(' ', '_', :g) }#%l<language>";

        $entry = $page.comb(rx:i/'=={{header|' $(%l<header>) '}}==' .+? [<?before \n'=='<-[={]>*'{{header'> || $] /).Str //
          uh-oh("No code found\nMay be bad markup", 'warn');

        if $entry ~~ /^^ 'See [[' (.+?) '/' $(%l<language>) / { # no code on main page, check sub page
            $entry = $client.get("{ $url }/index.php?title={ uri-escape $/[0].Str ~ '/' ~ %l<language> }&action=raw").content;
        }
        mkdir $taskdir unless $taskdir.IO.d;
        spurt( "$taskdir/$name.txt", $entry );
    } else {
        if "$taskdir/$name.txt".IO.e {
            $entry = "$taskdir/$name.txt".IO.slurp;
            say "Loading code from: $taskdir/$name.txt";
        } else {
            uh-oh("Task code $taskdir/$name.txt not found, check spelling or run remote.", 'warn');
            next;
        }
    }

    my @blocks = $entry.comb: %l<tag>;

    unless @blocks {
        uh-oh("No code found\nMay be bad markup", 'warn') unless %resource{"$name"}<skip> ~~ /'ok to skip'/;
        say "Skipping $name: ", %resource{"$name"}<skip>, "\n" if %resource{"$name"}<skip>
    }

    for @blocks.kv -> $k, $v {
        my $n = +@blocks == 1 ?? '' !! $k;
        spurt( "$taskdir/$name$n%l<ext>", $v );
        if %resource{"$name$n"}<skip> && !$force {
            dump-code ("$taskdir/$name$n%l<ext>");
            if %resource{"$name$n"}<skip> ~~ /'broken'/ {
                uh-oh(%resource{"$name$n"}<skip>, 'bad');
                pause if $broken;
            } else {
                say "{%c<warn>}Skipping $name$n: ", %resource{"$name$n"}<skip>, "{%c<clr>}\n";
            }
            next;
        }
        say "\nTesting $name$n";
        run-it($taskdir, "$name$n", $tasknum);
    }
    say  %c<delim>, '=' x 79, %c<clr>;
    redo if $redo;
    sleep $sleep if $sleep;
    pause if $pause;
}

## SUBROUTINES

sub mediawiki-query ($site, $type, *%query) {
    my $url = "$site/api.php?" ~ uri-query-string(
        :action<query>, :format<json>, :formatversion<2>, |%query);
    my $continue = '';

    gather loop {
        my $response = $client.get("$url&$continue");
        my $data = from-json($response.content);
        take $_ for $data.<query>.{$type}.values;
        $continue = uri-query-string |($data.<query-continue>{*}».hash.hash or last);
    }
}

sub run-it ($dir, $code, $tasknum) {
    my $current = $*CWD;
    chdir $dir;
    if %resource{$code}<file> -> $fn {
        copy "$current/rc/resources/{$_}", "./{$_}" for $fn[]
    }
    dump-code ("$code%l<ext>") unless $quiet;
    check-dependencies("$code%l<ext>", $lang) if $deps;
    my @cmd = %resource{$code}<cmd> ?? |%resource{$code}<cmd> !! "%l<exe> $code%l<ext>\n";
    if $timer {
        $tfile = open :a, "{$current}/{$lang}-time.txt";
    }
    my $time = 'NA: not run or killed before completion';
    for @cmd -> $cmd {
        say "\nCommand line: {%c<cmd>}$cmd",%c<clr>;
        if $timer { $tfile.say: "Command line: $cmd".chomp }
        my $start = now;
        try shell $cmd;
        $time = (now - $start).round(.001);
        CATCH {
            when /'exit code: 137'/ { }
            default {
                .resume unless $broken;
                uh-oh($_, 'bad');
                if %resource{$code}<fail-by-design> {
                    say %c<warn>, 'Fails by design, (or at least, it\'s not unexpected).', %c<clr>;
                } else {
                    if pause.lc eq 'r' {
                       unlink "$code.txt";
                       $redo = True;
                    }
                }
             }
        }
    if $timer { $tfile.say("#$tasknum - Wallclock seconds: $time\n") }
    }
    chdir $current;
    say "\nDone task #$tasknum: $code - wallclock seconds: $time\e[?25h";
    $tfile.close if $timer;
}

sub pause {
    prompt "Press enter to procede:> ";
    # or
    # sleep 5;
}

sub dump-code ($fn) {
    say "\n", %c<delim>, ('vvvvvvvv' xx 7).join(' CODE '), %c<clr>, "\n", %c<code>;
    print $fn.IO.slurp;
    say %c<clr>,"\n\n",%c<delim>,('^^^^^^^^' xx 7).join(' CODE '),%c<clr>;
}

sub uri-query-string (*%fields) { %fields.map({ "{.key}={uri-escape .value}" }).join('&') }

sub clear { "\r" ~ ' ' x 100 ~ "\r" }

sub uh-oh ($err, $class='warn') { put %c{$class}, "{'#' x 79}\n\n $err \n\n{'#' x 79}", %c<clr> }

sub fuzzy-search ($title) {
    my @tasknames;
    if "%l<dir>.tasks".IO.e {
        @tasknames = "%l<dir>.tasks".IO.slurp.lines;
    }
    return '' unless @tasknames.elems;
    " Did you perhaps mean:\n\n\t" ~
    @tasknames.grep( {.lc.contains($title.lc) or dld($_, $title) < (5 min $title.chars)} ).join("\n\t");
}                # Damerau Levenshtein distance  ^^^

multi check-dependencies ($fn, 'perl6') {
    my @use = $fn.IO.slurp.comb(/<?after ^^ \h* 'use '> \N+? <?before \h* ';'>/);
    if +@use {
        say %c<dep>, 'Checking dependencies...', %c<clr>;
        for @use -> $module {
            if $module eq any('v6', 'v6.c', 'v6.d', 'nqp', 'NativeCall', 'Test') or $module.contains('MONKEY')
              or $module.contains('experimental') or $module.starts-with('lib') or $module.contains('from<Perl5>') {
                print %c<dep>;
                say 'ok, no installation necessary: ', $module;
                print %c<clr>;
                next;
            }
            my $installed = $*REPO.resolve(CompUnit::DependencySpecification.new(:short-name($module)));
            my @mods = $module;
            if './../../../perl6-modules.txt'.IO.e {
                my $fh = open( './../../../perl6-modules.txt', :r ) or die $fh;
                @mods.append: $fh.lines;
                $fh.close;
            }
            my $fh = open( './../../../perl6-modules.txt', :w ) or die $fh;
            $fh.spurt: @mods.Bag.keys.sort.join: "\n";
            $fh.close;
            print %c<dep>;
            if $installed {
                say 'ok, installed: ', $module
            } else {
                say 'not installed: ', $module;
                shell("zef install $module");
            }
            print %c<clr>;
        }
    }
}

multi check-dependencies ($fn, 'perl') {
    my @use = $fn.IO.slurp.comb(/<?after ^^ \h* 'use '> \N+? <?before \h* ';'>/);
    if +@use {
        for @use -> $module {
            next if $module eq $module.lc;
            next if $module.starts-with(any('constant','bignum'));
            my $installed = shell( "%l<exe> -e 'eval \"use {$module}\"; exit 1 if \$@'" );
            print %c<dep>;
            if $installed {
                say 'ok:            ', $module
            } else {
                say 'not installed: ', $module;
                try shell("sudo cpan $module");
            }
            print %c<clr>;
        }
    }
}

multi check-dependencies  ($fn, $unknown) {
    note "Sorry, don't know how to handle dependencies for $unknown language."
};

multi load-lang ('perl6') { ( # Language specific variables. Adjust to suit.
    language => 'Perl_6', # language category name
    exe      => 'perl6',  # executable name to run perl6 in a shell
    ext      => '.p6',    # file extension for perl6 code
    dir      => 'perl6',  # directory to save tasks to
    header   => 'Perl 6', # header text
    # tags marking blocks of code - spaced out to placate wiki formatter
    # and to avoid getting tripped up when trying to run _this_ task
    tag => rx/<?after '<lang ' 'perl6' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ('perl') { (
    language => 'Perl',
    exe      => 'perl',
    ext      => '.pl',
    dir      => 'perl',
    header   => 'Perl',
    tag => rx/:i <?after '<lang ' 'perl' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ('python') { (
    language => 'Python',
    exe      => 'python',
    ext      => '.py',
    dir      => 'python',
    header   => 'Python',
    tag => rx/:i <?after '<lang ' 'python' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ('go') { (
    language => 'Go',
    exe      => 'go run',
    ext      => '.go',
    dir      => 'go',
    header   => 'Go',
    tag => rx/:i <?after '<lang ' 'go' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ('tcl') { (
    language => 'Tcl',
    exe      => 'tclsh',
    ext      => '.tcl',
    dir      => 'tcl',
    header   => 'Tcl',
    tag => rx/:i <?after '<lang ' 'tcl' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ($unknown) { die "Sorry, don't know how to handle $unknown language." };

multi load-resources ($unknown) { () };

multi load-resources ('perl6') { (
# Broken tasks
    'Amb1' => {'skip' => 'broken'},
    'Amb2' => {'skip' => 'broken'},
    'Median_filter' => {'skip' => 'broken (needs version on github <https://github.com/azawawi/perl6-magickwand> not CPAN)'},
    'Modular_arithmetic' => {'skip' => 'broken (module wont install, pull request pending)'},

# Normal tasks
    '4-rings_or_4-squares_puzzle' =>{'cmd' => "ulimit -t 5\n%l<exe> 4-rings_or_4-squares_puzzle%l<ext>"},
    '9_billion_names_of_God_the_integer' => {'cmd' => "ulimit -t 10\n%l<exe> 9_billion_names_of_God_the_integer%l<ext>"},
    'A_B0' => {'cmd' => "echo '13 9' | %l<exe> A_B0%l<ext>"},
    'A_B1' => {'cmd' => "echo '13 9' | %l<exe> A_B1%l<ext>"},
    'A_B2' => {'cmd' => "echo '13 9' | %l<exe> A_B2%l<ext>"},
    'Abbreviations__automatic' => {'file' => 'DoWAKA.txt'},
    'Accumulator_factory1' => {'skip' => 'fragment'},
    'Active Directory/Search for a user' => {'skip' => 'module not in ecosystem yet'},
    'Active_Directory_Connect' => {'skip' => 'fragment'},
    'Addition_chains' => {'cmd' => "ulimit -t 10\n%l<exe> Addition_chains%l<ext>"},
    'Align_columns1' => {'file' => 'Align_columns1.txt', 'cmd' => "%l<exe> Align_columns1%l<ext> left Align_columns1.txt"},
    'Anagrams0' => {'file' => 'unixdict.txt'},
    'Anagrams1' => {'file' => 'unixdict.txt'},
    'Anagrams_Deranged_anagrams' => {'file' => 'unixdict.txt'},
    'Animate_a_pendulum' => {'cmd' => "ulimit -t 2\n%l<exe> Animate_a_pendulum%l<ext>\n"},
    'Animation' => {'cmd' => "ulimit -t 1\n%l<exe> Animation%l<ext>\n"},
    'Arena_storage_pool' => {'skip' => 'ok to skip; no code'},
    'Arithmetic_Integer' => {'cmd' => "echo \"27\n31\n\" | %l<exe> Arithmetic_Integer%l<ext>"},
    'Arithmetic_Rational0' => {'cmd' => "ulimit -t 10\n%l<exe> Arithmetic_Rational0%l<ext>"},
    'Array_concatenation' => { :fail-by-design },
    'Array_length1' => { :fail-by-design },
    'Aspect_Oriented_Programming' => {'skip' => 'ok to skip; no code'},
    'Assertions0' => { :fail-by-design },
    'Assertions1' => {'skip' => 'macros NYI'},
    'Assertions_in_design_by_contract' => { :fail-by-design },
    'Atomic_updates' => {'cmd' => "ulimit -t 10\n%l<exe> Atomic_updates%l<ext>\n"},
    'Balanced_brackets0' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets0%l<ext>"},
    'Balanced_brackets1' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets1%l<ext>"},
    'Balanced_brackets2' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets2%l<ext>"},
    'Balanced_brackets3' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets3%l<ext>"},
    'Base64_encode_data' => { 'file' => 'favicon.ico' },
    'Binary_search0' => {'skip' => 'fragment'},
    'Birthday_problem' => {'cmd' => "ulimit -t 5\n%l<exe> Birthday_problem%l<ext>\n"},
    'CSV_data_manipulation0' => {'file' => 'whatever.csv'},
    'CSV_data_manipulation1' => {'skip' => 'fragment'},
    'Call_a_function0' => {'skip' => 'fragment'},
    'Call_a_function1' => {'skip' => 'fragment'},
    'Call_a_function2' => {'skip' => 'fragment'},
    'Call_a_function3' => {'skip' => 'fragment'},
    'Call_a_function4' => {'skip' => 'fragment'},
    'Call_a_function5' => {'skip' => 'fragment'},
    'Call_a_function6' => {'skip' => 'fragment'},
    'Call_a_function7' => {'skip' => 'fragment'},
    'Call_a_function8' => {'skip' => 'fragment'},
    'Call_a_function9' => {'skip' => 'fragment'},
    'Chat_server' => {'skip' => 'runs forever'},
    'Check_output_device_is_a_terminal' => {'skip' => 'ok to skip; no code'},
    'Checksumcolor' => {'cmd' => ["md5sum *.* | %l<exe> Checksumcolor%l<ext>"]},
    'Chowla_numbers' => {'cmd' => "ulimit -t 20\n%l<exe> Chowla_numbers%l<ext>"},
    'Code_segment_unload' => {'skip' => 'no code'},
    'Color_of_a_screen_pixel1' => {'cmd' => "%l<exe> Color_of_a_screen_pixel1%l<ext> 4 4 h\n"},
    'Command-line_arguments' => {'skip' => 'ok to skip; no code'},
    'Compare_a_list_of_strings' => {'skip' => 'fragment'},
    'Compiler_lexical_analyzer' => {'file' => 'test-case-3.txt','cmd' => "%l<exe> Compiler_lexical_analyzer%l<ext> test-case-3.txt"},
    'Compound_data_type0' => {'skip' => 'fragment'},
    'Compound_data_type1' => {'skip' => 'fragment'},
    'Conditional_structures0' => {'skip' => 'fragment'},
    'Conditional_structures1' => {'skip' => 'user input'},
    'Conditional_structures2' => {'skip' => 'fragment'},
    'Copy_a_string2' => {'skip' => 'nyi'},
    'Copy_stdin_to_stdout0' => {'skip' => 'shell code'},
    'Copy_stdin_to_stdout1' => {'skip' => 'user interaction'},
    'Count_in_factors0' => {'cmd' => "ulimit -t 1\n%l<exe> Count_in_factors0%l<ext>\n"},
    'Count_in_octal' => {'cmd' => "ulimit -t 1\n%l<exe> Count_in_octal%l<ext>\n"},
    'Create_a_file' => { :fail-by-design('or-at-least-expected') },
    'Create_a_file_on_magnetic_tape' => {'skip' => 'need a tape device attached'},
    'Create_a_two-dimensional_array_at_runtime0' => {'cmd' => "echo \"5x35\n\" | %l<exe> Create_a_two-dimensional_array_at_runtime0%l<ext>"},
    'Create_a_two-dimensional_array_at_runtime1' => {'cmd' => "echo \"3x10\n\" | %l<exe> Create_a_two-dimensional_array_at_runtime1%l<ext>"},
    'Create_an_object_Native_demonstration0' => { :fail-by-design },
    'Create_an_object_Native_demonstration1' => { :fail-by-design },
    'Cuban_primes0' => {'cmd' => "ulimit -t 2\n%l<exe> Cuban_primes0%l<ext>"},
    'Cyclotomic_Polynomial' => {'cmd' => "ulimit -t 15\n%l<exe> Cyclotomic_Polynomial%l<ext>"},
    'Decision_tables' => {'skip' => 'user interaction'},
    'Define_a_primitive_data_type0' => { :fail-by-design },
    'Delete_a_file' => {'cmd' => ["touch input.txt\n","mkdir docs\n","ls .\n","%l<exe> Delete_a_file%l<ext>\n","ls .\n"]},
    'Detect_division_by_zero0' => { :fail-by-design },
    'Dining_philosophers' => {'cmd' => "ulimit -t 1\n%l<exe> Dining_philosophers%l<ext>"},
    'Distributed_programming0' => {'skip' => 'runs forever'},
    'Distributed_programming1' => {'skip' => 'needs a server instance'},
    'Doubly-linked_list_Traversal' => {'skip' => 'fragment'},
    'Draw_a_clock' => {'cmd' => "ulimit -t 1\n%l<exe> Draw_a_clock%l<ext>\n"},
    'Draw_a_rotating_cube' => {'cmd' => "ulimit -t 10\n%l<exe> Draw_a_rotating_cube%l<ext>\n"},
    'Dynamic_variable_names' => {'cmd' => "echo \"this-var\" | %l<exe> Dynamic_variable_names%l<ext>"},
    'Echo_server0' => {'skip' => 'runs forever'},
    'Echo_server1' => {'skip' => 'runs forever'},
    'Elementary_cellular_automaton_Infinite_length' => {'cmd' => "ulimit -t 2\n%l<exe> Elementary_cellular_automaton_Infinite_length%l<ext>\n"},
    'Emirp_primes' => {'cmd' => ["%l<exe> Emirp_primes%l<ext> 1 20 \n","%l<exe> Emirp_primes%l<ext> 7700 8000 values\n"]},
    'Enforced_immutability3' => {'skip' => 'fragment'},
    'Equilibrium_index2' => {'skip' => 'fragment'},
    'Exceptions_Catch_an_exception_thrown_in_a_nested_call' => { :fail-by-design },
    'Executable_library1' => {'skip' => 'need to install library'},
    'Execute_HQ9_1' => {'skip' => 'user interaction'},
    'Extract_file_extension0' => {'skip' => 'fragment'},
    'Fibonacci_matrix-exponentiation' => {'cmd' => "ulimit -t 10\n%l<exe> Fibonacci_matrix-exponentiation%l<ext>"},
    'Fibonacci_sequence1' => {'skip' => 'fragment'},
    'Fibonacci_sequence2' => {'skip' => 'fragment'},
    'File_input_output0' => {'cmd' => ["cal > input.txt\n","%l<exe> File_input_output0%l<ext>"]},
    'File_input_output1' => {'cmd' => ["cal > input.txt\n","%l<exe> File_input_output1%l<ext>"]},
    'File_modification_time' => {'cmd' => "%l<exe> File_modification_time%l<ext> File_modification_time%l<ext>"},
    'File_size0' => {'cmd' => ["cal 2018 > input.txt\n", "%l<exe> File_size0%l<ext>"], :fail-by-design('or-at-least-expected') },
    'File_size1' => { :fail-by-design('or-at-least-expected') },
    'File_size_distribution' => {'cmd' => "%l<exe> File_size_distribution%l<ext> '..'"},
    'Find_largest_left_truncatable_prime_in_a_given_base' => {'cmd' => "ulimit -t 15\n%l<exe> Find_largest_left_truncatable_prime_in_a_given_base%l<ext>"},
    'Find_limit_of_recursion' => {'cmd' => "ulimit -t 6\n%l<exe> Find_limit_of_recursion%l<ext>\n"},
    'Finite_state_machine' => {'skip' => 'user interaction'},
    'First_perfect_square_in_base_N_with_N_unique_digits' =>{'cmd' => "ulimit -t 12\n%l<exe> First_perfect_square_in_base_N_with_N_unique_digits%l<ext>"},
    'Fixed_length_records' => {'file' => 'flr-infile.dat', 'cmd' => "%l<exe> Fixed_length_records%l<ext> < flr-infile.dat\n"},
    'Flow-control_structures' => {'skip' => 'nyi'},
    'Forest_fire0' => {'cmd' => ["ulimit -t 10\n%l<exe> Forest_fire0%l<ext>\n","%l<exe> -e'print \"\e[0m\ \e[H\e[2J\"'"]},
    'Forest_fire1' => {'cmd' => ["ulimit -t 20\n%l<exe> Forest_fire1%l<ext>\n"]},
    'Four_is_the_number_of_letters_in_the____' => {'cmd' => "ulimit -t 13\n%l<exe> Four_is_the_number_of_letters_in_the____%l<ext>"},
    'Fraction_reduction' => {'cmd' => "ulimit -t 40\n%l<exe> Fraction_reduction%l<ext>\n"},
    'Fractran1' => {'cmd' => "ulimit -t 10\n%l<exe> Fractran1%l<ext>\n"},
    'Function_definition7' => {'skip' => 'fragment'},
    'Function_definition8' => {'skip' => 'fragment'},
    'Function_frequency' => {'cmd' => "%l<exe> Function_frequency%l<ext> Function_frequency%l<ext>"},
    'Generic_swap' => {'skip' => 'fragment'},
    'Get_system_command_output0' => {'skip' => 'fragment'},
    'Globally_replace_text_in_several_files' => { :fail-by-design('or-at-least-expected') },
    'Greatest_common_divisor3' => {'skip' => 'fragment'},
    'Greatest_common_divisor4' => {'skip' => 'fragment'},
    'HTTPS0' => {'skip' => 'large'},
    'HTTPS1' => {'skip' => 'large'},
    'HTTPS_Client-authenticated' => {'skip' => 'needs certificate set up'},
    'Handle_a_signal' => {'skip' => 'needs user intervention'},
    'Hello_world_Line_printer0' => {'skip' => 'needs line printer attached'},
    'Hello_world_Line_printer1' => {'skip' => 'needs line printer attached'},
    'Hello_world_Newbie' => {'skip' => 'ok to skip; no code'},
    'Hello_world_Web_server0' => {'skip' => 'runs forever'},
    'Hello_world_Web_server1' => {'skip' => 'runs forever'},
    'Here_document2' => {'skip' => 'fragment'},
    'Hickerson_series_of_almost_integers' => { :fail-by-design },
    'Horizontal_sundial_calculations' => {'cmd' => "echo \"-4.95\n-150.5\n-150\n\" | %l<exe> Horizontal_sundial_calculations%l<ext>"},
    'Humble_numbers' => {'cmd' => "ulimit -t 10\n%l<exe> Humble_numbers%l<ext>"},
    'I_before_E_except_after_C0' => {'file' => 'unixdict.txt', 'cmd' => "%l<exe> I_before_E_except_after_C0%l<ext>"},
    'I_before_E_except_after_C1' => {'file' => '1_2_all_freq.txt'},
    'Image_noise' => {'cmd' => "ulimit -t 10\n%l<exe> Image_noise%l<ext>\n"},
    'Include_a_file0' => {'skip' => 'fragment'},
    'Include_a_file1' => {'skip' => 'fragment'},
    'Include_a_file2' => {'skip' => 'fragment'},
    'Include_a_file3' => {'skip' => 'fragment'},
    'Increasing_gaps_between_consecutive_Niven_numbers' =>{'cmd' => "%l<exe> Increasing_gaps_between_consecutive_Niven_numbers%l<ext> 100000"},
    'Input_Output_for_Lines_of_Text0' => {
        'cmd' => "echo \"3\nhello\nhello world\nPack my Box with 5 dozen liquor jugs\" | %l<exe> Input_Output_for_Lines_of_Text0%l<ext>"
    },
    'Input_Output_for_Lines_of_Text1' => {
        'cmd' => "echo \"3\nhello\nhello world\nPack my Box with 5 dozen liquor jugs\" | %l<exe> Input_Output_for_Lines_of_Text1%l<ext>"
    },
    'Input_Output_for_Pairs_of_Numbers' => {
        'cmd' => "echo \"5\n1 2\n10 20\n-3 5\n100 2\n5 5\" | %l<exe> Input_Output_for_Pairs_of_Numbers%l<ext>"
    },
    'Input_loop0' => {'skip' => 'fragment'},
    'Input_loop1' => {'skip' => 'fragment'},
    'Input_loop2' => {'skip' => 'fragment'},
    'Input_loop3' => {'skip' => 'fragment'},
    'Input_loop4' => {'skip' => 'fragment'},
    'Integer_comparison0' => {'cmd' => "echo \"9\n17\" | %l<exe> Integer_comparison0%l<ext>"},
    'Integer_comparison1' => {'skip' => 'fragment'},
    'Integer_comparison2' => {'cmd' => "echo \"9\n17\" | %l<exe> Integer_comparison2%l<ext>"},
    'Integer_sequence' => {'cmd' => "ulimit -t 1\n%l<exe> Integer_sequence%l<ext>\n"},
    'Interactive_Help' => { :fail-by-design('or-at-least-expected') },
    'Interactive_programming' => {'skip' => 'fragment'},
    'Inverted_index' => {'file' => 'unixdict.txt','cmd' => "echo \"rosetta\ncode\nblargg\n\" | %l<exe> Inverted_index%l<ext> unixdict.txt\n"},
    'Inverted_syntax0' => {'skip' => 'fragment'},
    'Inverted_syntax1' => {'skip' => 'fragment'},
    'Inverted_syntax2' => {'skip' => 'fragment'},
    'Inverted_syntax3' => {'skip' => 'fragment'},
    'Inverted_syntax4' => {'skip' => 'fragment'},
    'Inverted_syntax5' => {'skip' => 'fragment'},
    'Inverted_syntax6' => {'skip' => 'fragment'},
    'Inverted_syntax7' => {'skip' => 'fragment'},
    'Iterated_digits_squaring0' => {'cmd' => "ulimit -t 5\n%l<exe> Iterated_digits_squaring0%l<ext>"},
    'Iterated_digits_squaring1' => {'cmd' => "ulimit -t 5\n%l<exe> Iterated_digits_squaring1%l<ext>"},
    'Iterated_digits_squaring2' => {'cmd' => "ulimit -t 5\n%l<exe> Iterated_digits_squaring2%l<ext>"},
    'Joystick_position' => {'skip' => 'user interaction'},
    'Jump_anywhere2' => { :fail-by-design },
    'Jump_anywhere3' => { :fail-by-design },
    'Kaprekar_numbers1' => {'cmd' => "ulimit -t 2\n%l<exe> Kaprekar_numbers1%l<ext>"},
    'Kaprekar_numbers2' => {'cmd' => "ulimit -t 2\n%l<exe> Kaprekar_numbers2%l<ext>"},
    'Keyboard_input_Flush_the_keyboard_buffer' => {'skip' => 'user interaction'},
    'Keyboard_input_Keypress_check' => {'skip' => 'user interaction'},
    'Keyboard_input_Obtain_a_Y_or_N_response' => {'skip' => 'user interaction, custom shell'},
    'Keyboard_macros' => {'skip' => 'user interaction, custom shell'},
    'Knapsack_problem_0-10' => {'cmd' => "ulimit -t 10\n%l<exe> Knapsack_problem_0-10%l<ext>"},
    'Knapsack_problem_Bounded0' => {'cmd' => "ulimit -t 10\n%l<exe> Knapsack_problem_Bounded0%l<ext>"},
    'Knuth_shuffle1' => {'skip' => 'fragment'},
    'Last_letter-first_letter' => {'cmd' => "ulimit -t 15\n%l<exe> Last_letter-first_letter%l<ext>"},
    'Latin_Squares_in_reduced_form' => {'cmd' => "ulimit -t 10\n%l<exe> Latin_Squares_in_reduced_form%l<ext>"},
    'Leap_year0' => {'skip' => 'fragment'},
    'Leap_year1' => {'skip' => 'fragment'},
    'Left_factorials0' => {'cmd' => "ulimit -t 10\n%l<exe> Left_factorials0%l<ext>"},
    'Letter_frequency' => {'file' => 'lemiz.txt', 'cmd' => "cat lemiz.txt | %l<exe> Letter_frequency%l<ext>"},
    'Linux_CPU_utilization' => {'skip' => 'takes forever to time out', 'cmd' => "ulimit -t 1\n%l<exe> Linux_CPU_utilization%l<ext>\n"},
    'Literals_Floating_point' => {'skip' => 'fragment'},
    'Literals_String2' => {'skip' => 'fragment'},
    'Long_primes' => {'cmd' => "ulimit -t 45\n%l<exe> Long_primes%l<ext>\n"},
    'Longest_Common_Substring' => {'cmd' => "%l<exe> Longest_Common_Substring%l<ext> thisisatest testing123testing"},
    'Longest_string_challenge' => {'cmd' => "echo \"a\nbb\nccc\nddd\nee\nf\nggg\n\" | %l<exe> Longest_string_challenge%l<ext>\n"},
    'Loop_over_multiple_arrays_simultaneously3' => {'skip' => 'stub'},
    'Loop_over_multiple_arrays_simultaneously4' => {'skip' => 'stub'},
    'Loops_Foreach0' => {'skip' => 'fragment'},
    'Loops_Foreach1' => {'skip' => 'fragment'},
    'Loops_Foreach2' => {'skip' => 'fragment'},
    'Loops_Infinite0' => {'cmd' => "ulimit -t 1\n%l<exe> Loops_Infinite0%l<ext>\n"},
    'Loops_Infinite1' => {'cmd' => "ulimit -t 1\n%l<exe> Loops_Infinite1%l<ext>\n"},
    'Lucas-Lehmer_test' => {'cmd' => "ulimit -t 10\n%l<exe> Lucas-Lehmer_test%l<ext>"},
    'Lucky_and_even_lucky_numbers' => {
        'cmd' => ["%l<exe> Lucky_and_even_lucky_numbers%l<ext> 20 , lucky\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 1 20\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 1 20 evenlucky\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 6000 -6100\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 6000 -6100 evenlucky\n"]
    },
    'Magic_8-Ball' => {'cmd' => "echo \"?\n?\n?\n?\n?\n\n\" | %l<exe> Magic_8-Ball%l<ext>\n"},
    'Magic_squares_of_doubly_even_order' => {'cmd' => "%l<exe> Magic_squares_of_doubly_even_order%l<ext> 12"},
    'Magic_squares_of_odd_order' => {'cmd' => "%l<exe> Magic_squares_of_odd_order%l<ext> 11"},
    'Magic_squares_of_singly_even_order' => {'cmd' => "%l<exe> Magic_squares_of_singly_even_order%l<ext> 10"},
    'Markov_chain_text_generator' => {'file' => 'alice_oz.txt','cmd' => "%l<exe> Markov_chain_text_generator%l<ext> < alice_oz.txt --n=3 --words=200"},
    'Matrix_Digital_Rain' => {'cmd' => "ulimit -t 15\n%l<exe> Matrix_Digital_Rain%l<ext>"},
    'Matrix_chain_multiplication' => {'cmd' => ["echo '1, 5, 25, 30, 100, 70, 2, 1, 100, 250, 1, 1000, 2' | %l<exe> Matrix_chain_multiplication%l<ext>"]},
    'Memory_layout_of_a_data_structure0' => {'skip' => 'speculation'},
    'Memory_layout_of_a_data_structure1' => {'skip' => 'speculation'},
    'Menu' => {'cmd' => "echo \"2\n\" | %l<exe> Menu%l<ext>\n"},
    'Metaprogramming2' => {'skip' => 'fragment'},
    'Metronome' => {'skip' => 'long'},
    'Modulinos' => {'cmd' => "%l<exe> Modulinos%l<ext> test"},
    'Morse_code' => {'cmd' => "echo \"Howdy, World!\n\" | %l<exe> Morse_code%l<ext>\n"},
    'Mouse_position0' => {'skip' => 'jvm only'},
    'Multiple_distinct_objects' => {'skip' => 'fragment'},
    'Multiple_regression' => {'cmd' => "ulimit -t 10\n%l<exe> Multiple_regression%l<ext>"},
    'Multiplicative_order' => {'cmd' => "%l<exe> Multiplicative_order%l<ext> test"},
    'Mutex' => {'skip' => 'fragment'},
    'Naming_conventions' => {'skip' => 'ok to skip; no code'},
    'Narcissist' => {'skip' => 'needs to run from command line'},
    'Narcissistic_decimal_number0' => {'cmd' => "ulimit -t 10\n%l<exe> Narcissistic_decimal_number0%l<ext>"},
    'Narcissistic_decimal_number1' => {'cmd' => "ulimit -t 10\n%l<exe> Narcissistic_decimal_number1%l<ext>"},
    'Nautical_bell' => {'skip' => 'long (24 hours)'},
    'Null_object2' => { :fail-by-design },
    'Number_names0' => {'skip' => 'user interaction'},
    'Numerical_integration' => {'cmd' => "ulimit -t 5\n%l<exe> Numerical_integration%l<ext>"},
    'Odd_word_problem' => {'cmd' => ["echo 'we,are;not,in,kansas;any,more.' | %l<exe> Odd_word_problem%l<ext>\n",
                                     "echo 'what,is,the;meaning,of:life.' | %l<exe> Odd_word_problem%l<ext>\n"]
    },
    'One-time_pad0' => {'skip' => 'user interaction, manual intervention'},
    'One-time_pad1' => {'skip' => 'user interaction, manual intervention'},
    'OpenGL' => {'cmd' => "ulimit -t 2\n%l<exe> OpenGL%l<ext>"},
    'Operator_precedence' => {'skip' => 'ok to skip; no code'},
    'Optional_parameters0' => {'skip' => 'fragment'},
    'Optional_parameters1' => {'skip' => 'fragment'},
    'Ordered_words' => {'file' => 'unixdict.txt','cmd' => "%l<exe> Ordered_words%l<ext> < unixdict.txt"},
    'Parallel_Brute_Force1' => {'skip' => 'fragment'},
    'Parametrized_SQL_statement' => {'skip' => 'needs a database'},
    'Percolation_Mean_cluster_density' => {'cmd' => "ulimit -t 10\n%l<exe> Percolation_Mean_cluster_density%l<ext>"},
    'Pi' => {'cmd' => "ulimit -t 5\n%l<exe> Pi%l<ext>\n"},
    'Pick_random_element3' => {'skip' => 'fragment'},
    'Pierpont_primes' => {'cmd' => "ulimit -t 10\n%l<exe> Pierpont_primes%l<ext>"},
    'Pointers_and_references' => {'skip' => 'fragment'},
    'Polymorphism1' => {'skip' => 'fragment'},
    'Price_fraction0' => {'cmd' => "echo \".86\" | %l<exe> Price_fraction0%l<ext>\n"},
    'Price_fraction1' => {'cmd' => "echo \".74\" | %l<exe> Price_fraction1%l<ext>\n"},
    'Price_fraction2' => {'cmd' => "echo \".35\" | %l<exe> Price_fraction2%l<ext>\n"},
    'Prime_conspiracy' => {'cmd' => "ulimit -t 10\n%l<exe> Prime_conspiracy%l<ext>"},
    'Primes_-_allocate_descendants_to_their_ancestors' => {'cmd' => "ulimit -t 10\n%l<exe> Primes_-_allocate_descendants_to_their_ancestors%l<ext>"},
    'Primorial_numbers0' => {'cmd' => "ulimit -t 10\n%l<exe> Primorial_numbers0%l<ext>"},
    'Primorial_numbers1' => {'cmd' => "ulimit -t 10\n%l<exe> Primorial_numbers1%l<ext>"},
    'Program_termination' => {'skip' => 'fragment'},
    'Pythagorean_quadruples' => {'cmd' => "ulimit -t 10\n%l<exe> Pythagorean_quadruples%l<ext>"},
    'Pythagorean_triples1' => {'cmd' => "ulimit -t 1\n%l<exe> Pythagorean_triples1%l<ext>\n"},
    'Pythagorean_triples2' => {'cmd' => "ulimit -t 8\n%l<exe> Pythagorean_triples2%l<ext>\n"},
    'Pythagorean_triples3' => {'cmd' => "ulimit -t 8\n%l<exe> Pythagorean_triples3%l<ext>\n"},
    'Random_number_generator__included_' => {'skip' => 'ok to skip; no code'},
    'Raster_bars' => {'cmd' => ["ulimit -t 5\n%l<exe> Raster_bars%l<ext>\n"]},
    'Read_a_configuration_file' => {'file' => 'file.cfg','cmd' => ["cat file.cfg\n", "%l<exe> Read_a_configuration_file%l<ext>"]},
    'Read_a_file_character_by_character_UTF80' => {'file' => 'whatever','cmd' => "cat whatever | %l<exe> Read_a_file_character_by_character_UTF80%l<ext>"},
    'Read_a_file_character_by_character_UTF81' => {'file' => 'whatever','cmd' => "%l<exe> Read_a_file_character_by_character_UTF81%l<ext>"},
    'Read_a_file_line_by_line0' => {'cmd' => ["cal > test.txt\n","%l<exe> Read_a_file_line_by_line0%l<ext>"]},
    'Read_a_file_line_by_line1' => {'cmd' => ["cal > test.txt\n","%l<exe> Read_a_file_line_by_line1%l<ext>"]},
    'Read_a_specific_line_from_a_file' => {'cmd' => ["cal 2018 > cal.txt\n", "%l<exe> Read_a_specific_line_from_a_file%l<ext> cal.txt"]},
    'Readline_interface' => {'skip' => 'ok to skip; no code'},
    'Recursive_descent_parser_generator‎' => {'skip' => 'no code'},
    'Remove_lines_from_a_file' => {'cmd' => ["cal > foo\n","cat foo\n","%l<exe> Remove_lines_from_a_file%l<ext> foo 1 2\n","cat foo"]},
    'Rename_a_file' => {'cmd' => ["touch input.txt\n", "mkdir docs\n", "%l<exe> Rename_a_file%l<ext>\n", "ls ."], :fail-by-design('or-at-least-expected')},
    'Retrieve_and_search_chat_history' => {'cmd' => "%l<exe> Retrieve_and_search_chat_history%l<ext> github"},
    'Reverse_words_in_a_string' => { 'file' => 'reverse.txt','cmd' => "%l<exe> Reverse_words_in_a_string%l<ext> reverse.txt"},
    'Rosetta_Code_Count_examples' => {'skip' => 'long & tested often'},
    'Rosetta_Code_Find_bare_lang_tags' => {'file' => 'rcpage','cmd' => "%l<exe> Rosetta_Code_Find_bare_lang_tags%l<ext> rcpage"},
    'Rosetta_Code_Fix_code_tags0' => {'file' => 'rcpage','cmd' => "%l<exe> Rosetta_Code_Fix_code_tags0%l<ext> rcpage"},
    'Rosetta_Code_Fix_code_tags1' => {'file' => 'rcpage','cmd' => "%l<exe> Rosetta_Code_Fix_code_tags1%l<ext> rcpage"},
    'Rosetta_Code_List_authors_of_task_descriptions' => {'skip' => 'long & tested often'},
    'Rosetta_Code_Run_examples' => {'skip' => 'it\'s this task!'},
    'Rosetta_Code_Tasks_without_examples' => {'skip' => 'long, net connection'},
    'Rot-13' => {cmd => "echo 'Rosetta Code' | %l<exe> Rot-13%l<ext>"},
    'Run_as_a_daemon_or_service' => {'skip' => 'runs forever'},
    'Safe_mode' => {'skip' => 'no code'},
    'Scope_modifiers0' => {'skip' => 'fragment'},
    'Selective_File_Copy' => {'file' => 'sfc.dat'},
    'Self-describing_numbers' => {'cmd' => "ulimit -t 10\n%l<exe> Self-describing_numbers%l<ext>"},
    'Self-hosting_compiler' => {'cmd' => "echo \"say 'hello World!'\" | %l<exe> Self-hosting_compiler%l<ext>"},
    'Self-referential_sequence' => {'cmd' => "ulimit -t 10\n%l<exe> Self-referential_sequence%l<ext>"},
    'Semordnilap' => {'file' => 'unixdict.txt'},
    'Send_email' => {'skip' => 'needs email server'},
    'Separate_the_house_number_from_the_street_name' => {'file' => 'addresses.txt',
        'cmd' => "cat addresses.txt | %l<exe> Separate_the_house_number_from_the_street_name%l<ext>"
    },
    'Shell_one-liner' => {'skip' => 'shell code'},
    'Shell_one_liner' => {'skip' => 'ok to skip; no code'},
    'Simple_database0' => {'skip' => 'runs forever'},
    'Simple_database1' => {'skip' => 'needs server instance'},
    'Singly-linked_list_Element_definition0' => {'skip' => 'fragment'},
    'Singly-linked_list_Element_insertion' => {'skip' => 'fragment'},
    'Singly-linked_list_Element_removal0' => {'skip' => 'fragment'},
    'Singly-linked_list_Element_removal1' => {'skip' => 'fragment'},
    'Singly-linked_list_Traversal2' => {'skip' => 'fragment'},
    'Singly-linked_list_Traversal3' => {'skip' => 'fragment'},
    'Sleep' => {'cmd' => "echo \"3.86\" | %l<exe> Sleep%l<ext>\n"},
    'Smarandache_prime-digital_sequence' =>{'cmd' => "ulimit -t 10\n%l<exe> Smarandache_prime-digital_sequence%l<ext>"},
    'Sockets' => { :fail-by-design('or-at-least-expected') },
    'Solve_a_Hidato_puzzle' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_a_Hidato_puzzle%l<ext>"},
    'Solve_a_Holy_Knight_s_tour' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_a_Holy_Knight_s_tour%l<ext>"},
    'Solve_a_Hopido_puzzle' => {'cmd' => "for n in {1..40}; do echo \"\f\"; done\n%l<exe> Solve_a_Hopido_puzzle%l<ext>"},
    'Solve_a_Numbrix_puzzle' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_a_Numbrix_puzzle%l<ext>"},
    'Solve_the_no_connection_puzzle' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_the_no_connection_puzzle%l<ext>"},
    'Sort_a_list_of_object_identifiers1' => {'skip' => 'fragment'},
    'Sort_a_list_of_object_identifiers2' => {'skip' => 'fragment'},
    'Sort_an_integer_array0' => {'skip' => 'fragment'},
    'Sort_an_integer_array1' => {'skip' => 'fragment'},
    'Sparkline_in_unicode' => {
        'cmd' => ["echo \"9 18 27 36 45 54 63 72 63 54 45 36 27 18 9\" | %l<exe> Sparkline_in_unicode%l<ext>\n",
                  "echo \"1.5, 0.5 3.5, 2.5 5.5, 4.5 7.5, 6.5\" | %l<exe> Sparkline_in_unicode%l<ext>\n",
                  "echo \"3 2 1 0 -1 -2 -3 -4 -3 -2 -1 0 1 2 3\" | %l<exe> Sparkline_in_unicode%l<ext>\n"]
    },
    'Special_characters' => {'skip' => 'ok to skip; no code'},
    'Special_variables0' => {'skip' => 'fragment'},
    'Special_variables1' => {'skip' => 'fragment'},
    'Special_variables2' => {'skip' => 'fragment'},
    'Spiral_matrix1' => {'skip' => 'fragment'},
    'Square-free_integers' => {'cmd' => "ulimit -t 10\n%l<exe> Square-free_integers%l<ext>\n"},
    'Stack' => {'skip' => 'fragment'},
    'Stair-climbing_puzzle' => {'skip' => 'fragment'},
    'Start_from_a_main_routine' => {'skip' => 'fragment'},
    'Stream_Merge' => {'skip' => 'needs input files'},
    'String_matching0' => {'skip' => 'fragment'},
    'String_matching1' => {'skip' => 'fragment'},
    'String_matching2' => {'skip' => 'fragment'},
    'String_matching3' => {'skip' => 'fragment'},
    'Strip_comments_from_a_string' => {'file' => 'comments.txt','cmd' => ["cat comments.txt\n","%l<exe> Strip_comments_from_a_string%l<ext> < comments.txt"]},
    'Sudoku1' => {'cmd' => "ulimit -t 15\n%l<exe> Sudoku1%l<ext>"},
    'Sum_of_a_series0' => {'skip' => 'fragment'},
    'Super-d_numbers' => {'cmd' => "ulimit -t 40\n%l<exe> Super-d_numbers%l<ext>"},
    'Synchronous_concurrency' => {'cmd' => ["cal 2018 > cal.txt\n","%l<exe> Synchronous_concurrency%l<ext> cal.txt"]},
    'Table_creation' => {'skip' => 'ok to skip; no code'},
    'Take_notes_on_the_command_line' => {'file' => 'notes.txt'},
    'Teacup_rim_text' => {'file' => 'unixdict.txt'},
    'Temperature_conversion0' => {'cmd' => "echo \"21\" | %l<exe> Temperature_conversion0%l<ext>\n"},
    'Temperature_conversion1' => {
        'cmd' => ["echo \"0\" | %l<exe> Temperature_conversion1%l<ext>\n",
                  "echo \"0c\" | %l<exe> Temperature_conversion1%l<ext>\n",
                  "echo \"212f\" | %l<exe> Temperature_conversion1%l<ext>\n",
                  "echo \"-40c\" | %l<exe> Temperature_conversion1%l<ext>\n"]
    },
    'Terminal_control_Positional_read' => {'skip' => 'user interaction'},
    'Terminal_control_Restricted_width_positional_input_No_wrapping' => {'skip' => 'user interaction'},
    'Terminal_control_Restricted_width_positional_input_With_wrapping' => {'skip' => 'user interaction'},
    'Text_processing_1' => {'file' => 'readings.txt', 'cmd' => "%l<exe> Text_processing_1%l<ext> < readings.txt"},
    'Text_processing_2' => {'file' => 'readings.txt', 'cmd' => "%l<exe> Text_processing_2%l<ext> < readings.txt"},
    'Text_processing_Max_licenses_in_use' => {'file' => 'mlijobs.txt',
        'cmd' => "%l<exe> Text_processing_Max_licenses_in_use%l<ext> < mlijobs.txt"
    },
    'Textonyms' => {'file' => 'unixdict.txt'},
    'Topswops' => {'cmd' => "ulimit -t 10\n%l<exe> Topswops%l<ext>"},
    'Total_circles_area' => {'cmd' => "ulimit -t 10\n%l<exe> Total_circles_area%l<ext>"},
    'Trabb_Pardo_Knuth_algorithm' => {'cmd' => "echo \"10 -1 1 2 3 4 4.3 4.305 4.303 4.302 4.301\" | %l<exe> Trabb_Pardo_Knuth_algorithm%l<ext>\n"},
    'Truncate_a_file0' => {'cmd' => ["cal > foo\n","cat foo\n","%l<exe> Truncate_a_file0%l<ext> foo 69\n","cat foo"]},
    'Truncate_a_file1' => {'skip' => 'fragment'},
    'Truth_table' => {
        'cmd' => ["%l<exe> Truth_table%l<ext> 'A ^ B'\n",
                  "%l<exe> Truth_table%l<ext> 'foo & bar | baz'\n",
                  "%l<exe> Truth_table%l<ext> 'Jim & (Spock ^ Bones) | Scotty'\n"]
    },
    'URL_shortener' => {'skip' => 'runs forever'},
    'Untrusted_environment' => {'skip' => 'no code'},
    'Update_a_configuration_file' => {'file' => 'test.cfg',
        'cmd' => ["%l<exe> Update_a_configuration_file%l<ext> --/needspeeling --seedsremoved --numberofbananas=1024 --numberofstrawberries=62000 test.cfg\n",
                  "cat test.cfg\n"]
    },
    'User_defined_pipe_and_redirection_operators' => {'file' => 'List_of_computer_scientists.lst'},
    'User_input_Text' => {'cmd' => "echo \"Rosettacode\n10\" %l<exe> User_input_Text%l<ext> "},
    'Variable_size_Set' => {'skip' => 'ok to skip; no code'},
    'Variadic_function2' => {'skip' => 'fragment'},
    'Vibrating_rectangles0' => {'cmd' => ["ulimit -t 2\n%l<exe> Vibrating_rectangles0%l<ext>\n","%l<exe> -e'print \"\e[0H\e[0J\e[?25h\"'"]},
    'Vibrating_rectangles1' => {'cmd' => ["ulimit -t 5\n%l<exe> Vibrating_rectangles1%l<ext>\n"]},
    'Web_scraping' => {'skip' => 'site appears to be dead'},
    'Wireworld' => {'cmd' => "%l<exe> Wireworld%l<ext> --stop-on-repeat"},
    'Word_frequency' => {'file' => 'lemiz.txt', 'cmd' => "%l<exe> Word_frequency%l<ext> lemiz.txt 10"},
    'Word_search' => {'file' => 'unixdict.txt'},
    'Write_entire_file0' => {'skip' => 'fragment'},
    'Write_entire_file1' => {'skip' => 'fragment'},
    'Yahoo__search_interface' => {'cmd' => "%l<exe> Yahoo__search_interface%l<ext> test"},
    'Zhang-Suen_thinning_algorithm' => {'file' => 'rc-image.txt','cmd' => "%l<exe> Zhang-Suen_thinning_algorithm%l<ext> rc-image.txt"},
    'Zumkeller_numbers' => {'cmd' => "ulimit -t 10\n%l<exe> Zumkeller_numbers%l<ext>"},

# Game tasks
    '15_Puzzle_Game' => {'skip' => 'user interaction, game'},
    '2048' => {'skip' => 'user interaction, game'},
    '21_Game' => {'skip' => 'user interaction, game'},
    '24_game' => {'skip' => 'user interaction, game'},
    '24_game_Solve0' => {cmd => "echo 1399 | %l<exe> 24_game_Solve0%l<ext>"},
    '24_game_Solve1' => {cmd => "%l<exe> 24_game_Solve1%l<ext> 1399"},
    'Bulls_and_cows' => {'skip' => 'user interaction, game'},
    'Bulls_and_cows_Player' => {'skip' => 'user interaction, game'},
    'Flipping_bits_game' => {'skip' => 'user interaction, game'},
    'Go_Fish' => {'skip' => 'user interaction, game'},
    'Guess_the_number' => {'skip' => 'user interaction, game'},
    'Guess_the_number_With_feedback' => {'skip' => 'user interaction, game'},
    'Guess_the_number_With_feedback__player_' => {'skip' => 'user interaction, game'},
    'Hunt_The_Wumpus' => {'skip' => 'user interaction, game'},
    'Mad_Libs' => {'skip' => 'user interaction, game'},
    'Mastermind' => {'skip' => 'user interaction, game'},
    'Minesweeper_game' => {'skip' => 'user interaction, game'},
    'Nim_Game' => {'skip' => 'user interaction, game'},
    'Number_reversal_game' => {'skip' => 'user interaction, game'},
    'Penney_s_game' => {'skip' => 'user interaction, game'},
    'Pig_the_dice_game' => {'skip' => 'user interaction, game'},
    'RCRPG' => {'skip' => 'user interaction, game'},
    'Robots' => {'skip' => 'user interaction, game'},
    'Rock-paper-scissors0' => {'skip' => 'user interaction, game'},
    'Snake' => {'skip' => 'user interaction, game'},
    'Snake_And_Ladder' => {'skip' => 'user interaction, game'},
    'Spoof_game' => {'skip' => 'user interaction, game'},
    'Tic-tac-toe' => {'skip' => 'user interaction, game'},

# Image tasks
    'Archimedean_spiral' => {'cmd' => ["%l<exe> Archimedean_spiral%l<ext>\n","$view Archimedean-spiral-perl6.png"]},
    'Barnsley_fern' => {'cmd' => ["%l<exe> Barnsley_fern%l<ext>\n","$view Barnsley-fern-perl6.png"]},
    'Bilinear_interpolation' => {'file' => 'Lenna100.jpg', 'cmd' => ["%l<exe> Bilinear_interpolation%l<ext>", "$view Lenna100.jpg", "$view Lenna100-larger.jpg"]},
    'Bitmap_B_zier_curves_Cubic' => {'cmd' => ["%l<exe> Bitmap_B_zier_curves_Cubic%l<ext> > Bezier-cubic-perl6.ppm\n","$view Bezier-cubic-perl6.ppm"]},
    'Bitmap_B_zier_curves_Quadratic' => {'cmd' => ["%l<exe> Bitmap_B_zier_curves_Quadratic%l<ext> > Bezier-quadratic-perl6.ppm\n","$view Bezier-quadratic-perl6.ppm"]},
    'Bitmap_Flood_fill' => {'file' => 'Unfilled-Circle.ppm', 'cmd' => ["%l<exe> Bitmap_Flood_fill%l<ext>", "$view Unfilled-Circle.ppm", "$view Bitmap-flood-perl6.ppm"]},
    'Bitmap_Histogram' => {'file' => 'Lenna.ppm', 'cmd' => ["%l<exe> Bitmap_Histogram%l<ext>\n","$view Lenna-bw.pbm"]},
    'Bitmap_Read_a_PPM_file' => {'file' => 'camelia.ppm', 'cmd' => ["%l<exe> Bitmap_Read_a_PPM_file%l<ext>\n","$view camelia-gs.pgm"]},
    'Bitmap_Read_an_image_through_a_pipe' => {'file' => 'camelia.png', 'cmd' => ["%l<exe> Bitmap_Read_an_image_through_a_pipe%l<ext>\n","$view camelia.ppm"]},
    'Bitmap_Write_a_PPM_file' => {'cmd' => ["%l<exe> Bitmap_Write_a_PPM_file%l<ext> > Bitmap-write-ppm-perl6.ppm\n","$view Bitmap-write-ppm-perl6.ppm"]},
    'Chaos_game' => {'cmd' => ["%l<exe> Chaos_game%l<ext>\n","$view Chaos-game-perl6.png"]},
    'Color_quantization' => {'file' => 'Quantum_frog.png', 'cmd' => ["%l<exe> Color_quantization%l<ext>\n", "$view Quantum_frog.png", "$view Quantum-frog-16-perl6.png"]},
    'Color_wheel' => {'cmd' => ["%l<exe> Color_wheel%l<ext>\n","$view Color-wheel-perl6.png"]},
    'Colour_pinstripe_Printer' => {'cmd' => ["%l<exe> Colour_pinstripe_Printer%l<ext>\n","$view Color-pinstripe-printer-perl6.png"]},
    'Curve_that_touches_three_points' => {'cmd' => ["%l<exe> Curve_that_touches_three_points%l<ext>\n","$view Curve-3-points-perl6.png"]},
    'Death_Star' => {'cmd' => ["%l<exe> Death_Star%l<ext>\n","$view deathstar-perl6.pgm"]},
    'Dragon_curve' => {'cmd' => ["%l<exe> Dragon_curve%l<ext> > Dragon-curve-perl6.svg\n","$view Dragon-curve-perl6.svg"]},
    'Draw_a_sphere0' => {'cmd' => ["%l<exe> Draw_a_sphere0%l<ext>\n","$view sphere-perl6.pgm"]},
    'Draw_a_sphere1' => {'cmd' => ["%l<exe> Draw_a_sphere1%l<ext>\n","$view sphere2-perl6.png"]},
    'Fractal_tree' => {'cmd' => ["%l<exe> Fractal_tree%l<ext> > Fractal-tree-perl6.svg\n","$view Fractal-tree-perl6.svg"]},
    'Grayscale_image' => {'file' => 'default.ppm', 'cmd' => ["%l<exe> Grayscale_image%l<ext>\n","$view default.pgm"]},
    'Greyscale_bars_Display' => {'cmd' => ["%l<exe> Greyscale_bars_Display%l<ext>\n","$view Greyscale-bars-perl6.pgm"]},
    'Hilbert_curve0' => {'cmd' => ["%l<exe> Hilbert_curve0%l<ext> > Hilbert-curve-perl6.svg\n","$view Hilbert-curve-perl6.svg"]},
    'Hilbert_curve1' => {'cmd' => ["%l<exe> Hilbert_curve1%l<ext> > Moore-curve-perl6.svg\n","$view Moore-curve-perl6.svg"]},
    'Hough_transform' => {'file' => 'pentagon.ppm', 'cmd' => ["%l<exe> Hough_transform%l<ext>\n","$view hough-transform.png"]},
    'Image_convolution' => {'file' => 'Lenna100.jpg', 'cmd' => ["%l<exe> Image_convolution%l<ext>", "$view Lenna100.jpg", "$view Lenna100-convoluted.jpg"]},
    'Julia_set' => {'cmd' => ["%l<exe> Julia_set%l<ext>\n","$view Julia-set-perl6.png"]},
    'Koch_curve0' => {'cmd' => ["%l<exe> Koch_curve0%l<ext> > Koch_curve0-perl6.svg\n","$view Koch_curve0-perl6.svg"]},
    'Koch_curve1' => {'cmd' => ["%l<exe> Koch_curve1%l<ext> > Koch_curve1-perl6.svg\n","$view Koch_curve1-perl6.svg"]},
    'Kronecker_product_based_fractals' => {
        'cmd' => ["%l<exe> Kronecker_product_based_fractals%l<ext>\n",
                  "$view kronecker-vicsek-perl6.png",
                  "$view kronecker-carpet-perl6.png",
                  "$view kronecker-six-perl6.png",
                  ]
    },
    'Mandelbrot_set' => {'cmd' => ["%l<exe> Mandelbrot_set%l<ext> 255 > Mandelbrot-set-perl6.ppm\n","$view Mandelbrot-set-perl6.ppm"]},
    'Munching_squares0' => {'cmd' => ["%l<exe> Munching_squares0%l<ext>\n","$view munching0.ppm"]},
    'Munching_squares1' => {'cmd' => ["%l<exe> Munching_squares1%l<ext>\n","$view munching1.ppm"]},
    'Peano_curve' => {'cmd' => ["%l<exe> Peano_curve%l<ext> > Peano-curve-perl6.svg\n","$view Peano-curve-perl6.svg"]},
    'Penrose_tiling' => {'cmd' => ["%l<exe> Penrose_tiling%l<ext> > Penrose_tiling-perl6.svg\n","$view Penrose_tiling-perl6.svg"]},
    'Pentagram' => {'cmd' => ["%l<exe> Pentagram%l<ext> > Pentagram-perl6.svg\n","$view Pentagram-perl6.svg"]},
    'Percentage_difference_between_images' => {'file' => ['Lenna100.jpg','Lenna50.jpg'], 'cmd' => ["%l<exe> Percentage_difference_between_images%l<ext>", "$view Lenna100.jpg", "$view Lenna50.jpg"]},
    'Pinstripe_Display' => {'cmd' => ["%l<exe> Pinstripe_Display%l<ext>\n","$view pinstripes.pgm"]},
    'Pinstripe_Printer' => {'cmd' => ["%l<exe> Pinstripe_Printer%l<ext>\n","$view Pinstripe-printer-perl6.png"]},
    'Plasma_effect' => {'cmd' => ["%l<exe> Plasma_effect%l<ext>\n","$view Plasma-perl6.png"]},
    'Plot_coordinate_pairs' => {'cmd' => ["%l<exe> Plot_coordinate_pairs%l<ext> > Plot-coordinate-pairs-perl6.svg\n","$view Plot-coordinate-pairs-perl6.svg"]},
    'Polyspiral0' => { 'file' => 'polyspiral-perl6.svg',
        'cmd' => [
                  "$view polyspiral-perl6.svg",
                  "%l<exe> Polyspiral0%l<ext>\n",
                 ]
    },
    'Polyspiral1' => {'cmd' => "ulimit -t 25\n%l<exe> Polyspiral1%l<ext>\n"},
    'Pythagoras_tree' => {'cmd' => ["%l<exe> Pythagoras_tree%l<ext> > Pythagoras-tree-perl6.svg\n","$view Pythagoras-tree-perl6.svg"]},
    'Sierpinski_pentagon' => {'cmd' => ["%l<exe> Sierpinski_pentagon%l<ext>\n","$view sierpinski_pentagon.svg"]},
    'Sierpinski_triangle_Graphical' => {'cmd' => ["%l<exe> Sierpinski_triangle_Graphical%l<ext>","$view sierpinski_triangle.svg"]},
    'Sunflower_fractal' => {'cmd' => ["%l<exe> Sunflower_fractal%l<ext> > Sunflower-fractal-perl6.svg\n","$view Sunflower-fractal-perl6.svg"]},
    'Superellipse' => {'cmd' => ["%l<exe> Superellipse%l<ext> > Superellipse-perl6.svg\n","$view Superellipse-perl6.svg"]},
    'Sutherland-Hodgman_polygon_clipping' => {'cmd' => ["%l<exe> Sutherland-Hodgman_polygon_clipping%l<ext>", "$view Sutherland-Hodgman-polygon-clipping-perl6.svg"]},
    'Voronoi_diagram' => {
        'cmd' => ["%l<exe> Voronoi_diagram%l<ext>\n",
                  "$view Voronoi-Minkowski-perl6.png",
                      "$view Voronoi-Taxicab-perl6.png",
                  "$view Voronoi-Euclidean-perl6.png",
                 ]
    },
    'Yellowstone_sequence' => {
        'cmd' => ["%l<exe> Yellowstone_sequence%l<ext>\n",
                  "$view Yellowstone-sequence-line-perl6.svg",
                  "$view Yellowstone-sequence-bars-perl6.svg"
                  ]
    },
    'Yin_and_yang0' => {'cmd' => ["%l<exe> Yin_and_yang0%l<ext> > Yin_and_yang-perl6.svg\n","$view Yin_and_yang-perl6.svg"]},
)}
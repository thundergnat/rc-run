use HTTP::UserAgent;
use URI::Escape;
use JSON::Fast;
use MONKEY-SEE-NO-EVAL;

my %*SUB-MAIN-OPTS = :named-anywhere;

unit sub MAIN(
    Str $run = '',        # Task or file name
    Str :$lang = 'perl6', # Language, default perl6 - should be same as in <lang *> markup
    Int :$skip = 0,       # Skip # to continue partially into a list
    Bool :f(:$force),     # Override any task skip parameter in %resource hash
    Bool :l(:$local),     # Only use code from local cache
    Bool :r(:$remote),    # Only use code from remote server (refresh local cache)
    Bool :q(:$quiet),     # Less verbose, don't display source code
    Bool :d(:$deps),      # Load dependencies
    Bool :p(:$pause),     # pause after each task
    Bool :b(:$broken),     # pause after each task marked broken
);

die 'You can select local or remote, but not both...' if $local && $remote;

my $client   = HTTP::UserAgent.new;
my $url      = 'http://rosettacode.org/mw';

my %c = ( # text colors
    code  => "\e[0;92m", # green
    delim => "\e[0;93m", # yellow
    cmd   => "\e[1;96m", # cyan
    warn  => "\e[0;91m", # red
    clr   => "\e[0m",    # clear formatting
);

my $view      = 'xdg-open';       # image viewer, this will open default under Linux
my %l         = load-lang($lang); # load languge parameters
my %resource  = load-resources($lang);
my $get-tasks = True;

my @tasks;

run('clear');


if $run {
    if $run.IO.e and $run.IO.f {# is it a file?
        @tasks = $run.IO.lines; # yep, treat each line as a task name
    } else {                    # must be a single task name
        @tasks = ($run);        # treat it so
    }
    $get-tasks = False;         # don't need to retrieve task names from web
}

if $get-tasks { # load tasks from web if cache is not found, older than one day or forced
    if !"%l<dir>.tasks".IO.e or ("%l<dir>.tasks".IO.modified - now) > 86400 or $remote {
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

note "Skipping first $skip tasks..." if $skip;

for @tasks -> $title {
    next if $++ < $skip;
    next unless $title ~~ /\S/; # filter blank lines (from files)
    say $skip + ++$, ")  $title";

    my $name = $title.subst(/<-[-0..9A..Za..z]>/, '_', :g);
    my $taskdir = "./rc/%l<dir>/$name";

    my $modified = "$taskdir/$name.txt".IO.e ?? "$taskdir/$name.txt".IO.modified !! 0;

    my $entry;
    if $remote or !"$taskdir/$name.txt".IO.e or (($modified - now) > 86400 * 7) {
        my $page = $client.get("{ $url }/index.php?title={ uri-escape $title }&action=raw").content;

        uh-oh("Whoops, can't find page: $url/$title :check spelling.") and next if $page.elems == 0;
        say "Getting code from: http://rosettacode.org/wiki/{ $title.subst(' ', '_', :g) }#%l<language>";

        my $header = %l<header>; # can't interpolate hash into regex
        $entry = $page.comb(/'=={{header|' $header '}}==' .+? [<?before \n'=='<-[={]>*'{{header'> || $] /).Str //
          uh-oh("No code found\nMay be bad markup");

        my $lang = %l<language>; # can't interpolate hash into regex
        if $entry ~~ /^^ 'See [[' (.+?) '/' $lang / { # no code on main page, check sub page
            $entry = $client.get("{ $url }/index.php?title={ uri-escape $/[0].Str ~ '/' ~ %l<language> }&action=raw").content;
        }
        mkdir $taskdir unless $taskdir.IO.d;
        spurt( "$taskdir/$name.txt", $entry );
    } else {
        if "$taskdir/$name.txt".IO.e {
            $entry = "$taskdir/$name.txt".IO.slurp;
            say "Loading code from: $taskdir/$name.txt";
        } else {
            uh-oh("Task code $taskdir/$name.txt not found, check spelling or run remote.");
            next;
        }
    }

    my @blocks = $entry.comb: %l<tag>;

    unless @blocks {
        uh-oh("No code found\nMay be bad markup") unless %resource{"$name"}<skip> ~~ /'ok to skip'/;
        say "Skipping $name: ", %resource{"$name"}<skip>, "\n" if %resource{"$name"}<skip>
    }

    for @blocks.kv -> $k, $v {
        my $n = +@blocks == 1 ?? '' !! $k;
        spurt( "$taskdir/$name$n%l<ext>", $v );
        if %resource{"$name$n"}<skip> && !$force {
            dump-code ("$taskdir/$name$n%l<ext>");
            if %resource{"$name$n"}<skip> ~~ /'broken'/ {
                uh-oh(%resource{"$name$n"}<skip>);
                pause if $broken;
            } else {
                say "Skipping $name$n: ", %resource{"$name$n"}<skip>, "\n";
            }
            next;
        }
        say "\nTesting $name$n";
        run-it($taskdir, "$name$n");
    }
    say  %c<delim>, '=' x 79, %c<clr>;
    pause if $pause;

}

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

sub run-it ($dir, $code) {
    my $current = $*CWD;
    chdir $dir;
    if %resource{$code}<file> -> $fn {
        copy "$current/rc/resources/{$fn}", "./{$fn}"
    }
    dump-code ("$code%l<ext>") unless $quiet;
    check-dependencies("$code%l<ext>", $lang) if $deps;
    my @cmd = %resource{$code}<cmd> ?? |%resource{$code}<cmd> !! "%l<exe> $code%l<ext>\n";
    for @cmd -> $cmd {
        say "\nCommand line: {%c<cmd>}$cmd",%c<clr>;
        try shell $cmd;
    }
    chdir $current;
    say "\nDone $code";
}

sub pause {
    prompt "Press enter to procede:>";
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

sub uh-oh ($err) { put %c<warn>, "{'#' x 79}\n\n $err \n\n{'#' x 79}", %c<clr> }

multi check-dependencies ($fn, 'perl6') {
    my @use = $fn.IO.slurp.comb(/<?after $$ 'use '> \N+? <?before \h* ';'>/);
    if +@use {
        for @use -> $module {
            next if $module eq any('v6','nqp') or $module.contains('MONKEY');
            my $installed = $*REPO.resolve(CompUnit::DependencySpecification.new(:short-name($module)));
            shell("zef install $module") unless $installed;
        }
    }
}

multi check-dependencies  ($fn, $unknown) {
    note "Sorry, don't know how to handle dependancies for $unknown language."
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
    tag => rx/<?after '<lang ' 'perl' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ('python') { (
    language => 'Python',
    exe      => 'python',
    ext      => '.py',
    dir      => 'python',
    header   => 'Python',
    tag => rx/<?after '<lang ' 'python' '>' > .*? <?before '</' 'lang>'>/,
) }

multi load-lang ($unknown) { die "Sorry, don't know how to handle $unknown language." };

multi load-resources ($unknown) { () };

multi load-resources ('perl6') { (
    'Amb1' => {'skip' => 'broken'},
    'Amb2' => {'skip' => 'broken'},
    'Formal_power_series' => {'skip' => 'broken'},
    'Multiline_shebang' => {'skip' => 'broken'},
    'Names_to_numbers' => {'skip' => 'broken'},
    'Set_of_real_numbers' => {'skip' => 'broken'},
    'Singly-linked_list_Element_insertion' => {'skip' => 'broken'},
    'Sorting_algorithms_Strand_sort' => {'skip' => 'broken'},
    'Window_creation_X11' => {'skip' => 'broken'},
    'Modular_arithmetic' => {'skip' => 'broken (module wont install, pull request pending)'},
    'FTP' => {'skip' => 'broken'}, # fixed in Rakudo 2018.04
    'GUI_component_interaction' => {'skip' => 'broken module'},
    'GUI_enabling_disabling_of_controls' => {'skip' => 'broken module'},
    'Image_noise' => {'skip' => 'broken module'},
    'Retrieve_and_search_chat_history' => {'skip' => 'broken, fixed in Rakudo 2018.04'},

    'Accumulator_factory1' => {'skip' => 'fragment'},
    'Binary_search0' => {'skip' => 'fragment'},
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
    'Compare_a_list_of_strings' => {'skip' => 'fragment'},
    'Compound_data_type0' => {'skip' => 'fragment'},
    'Compound_data_type1' => {'skip' => 'fragment'},
    'Conditional_structures0' => {'skip' => 'fragment'},
    'Conditional_structures2' => {'skip' => 'fragment'},
    'Doubly-linked_list_Traversal' => {'skip' => 'fragment'},
    'Enforced_immutability3' => {'skip' => 'fragment'},
    'Equilibrium_index2' => {'skip' => 'fragment'},
    'Extract_file_extension0' => {'skip' => 'fragment'},
    'Fibonacci_sequence1' => {'skip' => 'fragment'},
    'Fibonacci_sequence2' => {'skip' => 'fragment'},
    'Function_definition7' => {'skip' => 'fragment'},
    'Function_definition8' => {'skip' => 'fragment'},
    'Generic_swap' => {'skip' => 'fragment'},
    'Get_system_command_output0' => {'skip' => 'fragment'},
    'Greatest_common_divisor3' => {'skip' => 'fragment'},
    'Greatest_common_divisor4' => {'skip' => 'fragment'},
    'Here_document2' => {'skip' => 'fragment'},
    'Include_a_file0' => {'skip' => 'fragment'},
    'Include_a_file1' => {'skip' => 'fragment'},
    'Include_a_file2' => {'skip' => 'fragment'},
    'Include_a_file3' => {'skip' => 'fragment'},
    'Input_loop0' => {'skip' => 'fragment'},
    'Input_loop1' => {'skip' => 'fragment'},
    'Input_loop2' => {'skip' => 'fragment'},
    'Input_loop3' => {'skip' => 'fragment'},
    'Input_loop4' => {'skip' => 'fragment'},
    'Integer_comparison1' => {'skip' => 'fragment'},
    'Interactive_programming' => {'skip' => 'fragment'},
    'Inverted_syntax0' => {'skip' => 'fragment'},
    'Inverted_syntax1' => {'skip' => 'fragment'},
    'Inverted_syntax2' => {'skip' => 'fragment'},
    'Inverted_syntax3' => {'skip' => 'fragment'},
    'Inverted_syntax4' => {'skip' => 'fragment'},
    'Inverted_syntax5' => {'skip' => 'fragment'},
    'Inverted_syntax6' => {'skip' => 'fragment'},
    'Inverted_syntax7' => {'skip' => 'fragment'},
    'Knuth_shuffle1' => {'skip' => 'fragment'},
    'Leap_year0' => {'skip' => 'fragment'},
    'Leap_year1' => {'skip' => 'fragment'},
    'Literals_Floating_point' => {'skip' => 'fragment'},
    'Literals_String2' => {'skip' => 'fragment'},
    'Loops_Foreach0' => {'skip' => 'fragment'},
    'Loops_Foreach1' => {'skip' => 'fragment'},
    'Loops_Foreach2' => {'skip' => 'fragment'},
    'Metaprogramming2' => {'skip' => 'fragment'},
    'Multiple_distinct_objects' => {'skip' => 'fragment'},
    'Mutex' => {'skip' => 'fragment'},
    'Optional_parameters' => {'skip' => 'fragment'},
    'Parallel_Brute_Force1' => {'skip' => 'fragment'},
    'Pick_random_element3' => {'skip' => 'fragment'},
    'Pointers_and_references' => {'skip' => 'fragment'},
    'Polymorphism1' => {'skip' => 'fragment'},
    'Program_termination' => {'skip' => 'fragment'},

    'Scope_modifiers0' => {'skip' => 'fragment'},
    'Singly-linked_list_Element_definition' => {'skip' => 'fragment'},
    'Sort_a_list_of_object_identifiers1' => {'skip' => 'fragment'},
    'Sort_a_list_of_object_identifiers2' => {'skip' => 'fragment'},
    'Sort_an_integer_array0' => {'skip' => 'fragment'},
    'Sort_an_integer_array1' => {'skip' => 'fragment'},
    'Special_variables0' => {'skip' => 'fragment'},
    'Special_variables1' => {'skip' => 'fragment'},
    'Special_variables2' => {'skip' => 'fragment'},
    'Spiral_matrix1' => {'skip' => 'fragment'},
    'Stack' => {'skip' => 'fragment'},
    'Stair-climbing_puzzle' => {'skip' => 'fragment'},
    'Start_from_a_main_routine' => {'skip' => 'fragment'},
    'String_matching0' => {'skip' => 'fragment'},
    'String_matching1' => {'skip' => 'fragment'},
    'String_matching2' => {'skip' => 'fragment'},
    'String_matching3' => {'skip' => 'fragment'},
    'Sum_of_a_series0' => {'skip' => 'fragment'},
    'Variadic_function2' => {'skip' => 'fragment'},
    'Write_entire_file0' => {'skip' => 'fragment'},
    'Write_entire_file1' => {'skip' => 'fragment'},

    'Mouse_position' => {'skip' => 'jvm only'},
    'HTTPS0' => {'skip' => 'large'},
    'HTTPS1' => {'skip' => 'large'},
    'Solve_a_Numbrix_puzzle' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_a_Numbrix_puzzle%l<ext>"},
    'Solve_a_Hidato_puzzle' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_a_Hidato_puzzle%l<ext>"},
    'Solve_a_Hopido_puzzle' => {'cmd' => "for n in {1..40}; do echo \"\f\"; done\n%l<exe> Solve_a_Hopido_puzzle%l<ext>"},
    'Solve_a_Holy_Knight_s_tour' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_a_Holy_Knight_s_tour%l<ext>"},
    'Solve_the_no_connection_puzzle' => {'cmd' => "for n in {1..35}; do echo \"\f\"; done\n%l<exe> Solve_the_no_connection_puzzle%l<ext>"},

    '9_billion_names_of_God_the_integer' => {'cmd' => "ulimit -t 10\n%l<exe> 9_billion_names_of_God_the_integer%l<ext>"},
    'Arithmetic_Rational0' => {'cmd' => "ulimit -t 10\n%l<exe> Arithmetic_Rational0%l<ext>"},
    'Dining_philosophers' => {'cmd' => "ulimit -t 1\n%l<exe> Dining_philosophers%l<ext>"},
    'Find_largest_left_truncatable_prime_in_a_given_base' => {'cmd' => "ulimit -t 15\n%l<exe> Find_largest_left_truncatable_prime_in_a_given_base%l<ext>"},
    'Four_is_the_number_of_letters_in_the____' => {'cmd' => "ulimit -t 13\n%l<exe> Four_is_the_number_of_letters_in_the____%l<ext>"},
    '4-rings_or_4-squares_puzzle' =>{'cmd' => "ulimit -t 5\n%l<exe> 4-rings_or_4-squares_puzzle%l<ext>"},
    'Iterated_digits_squaring0' => {'cmd' => "ulimit -t 5\n%l<exe> Iterated_digits_squaring0%l<ext>"},
    'Iterated_digits_squaring1' => {'cmd' => "ulimit -t 5\n%l<exe> Iterated_digits_squaring1%l<ext>"},
    'Iterated_digits_squaring2' => {'cmd' => "ulimit -t 5\n%l<exe> Iterated_digits_squaring2%l<ext>"},
    'Kaprekar_numbers1' => {'cmd' => "ulimit -t 2\n%l<exe> Kaprekar_numbers1%l<ext>"},
    'Kaprekar_numbers2' => {'cmd' => "ulimit -t 2\n%l<exe> Kaprekar_numbers2%l<ext>"},
    'Knapsack_problem_0-1' => {'cmd' => "ulimit -t 10\n%l<exe> Knapsack_problem_0-1%l<ext>"},
    'Knapsack_problem_Bounded' => {'cmd' => "ulimit -t 10\n%l<exe> Knapsack_problem_Bounded%l<ext>"},
    'Last_letter-first_letter' => {'cmd' => "ulimit -t 15\n%l<exe> Last_letter-first_letter%l<ext>"},
    'Left_factorials0' => {'cmd' => "ulimit -t 10\n%l<exe> Left_factorials0%l<ext>"},
    'Lucas-Lehmer_test' => {'cmd' => "ulimit -t 10\n%l<exe> Lucas-Lehmer_test%l<ext>"},
    'Metronome' => {'skip' => 'long'},
    'Multiple_regression' => {'cmd' => "ulimit -t 10\n%l<exe> Multiple_regression%l<ext>"},
    'Narcissistic_decimal_number0' => {'cmd' => "ulimit -t 10\n%l<exe> Narcissistic_decimal_number0%l<ext>"},
    'Narcissistic_decimal_number1' => {'cmd' => "ulimit -t 10\n%l<exe> Narcissistic_decimal_number1%l<ext>"},
    'Numerical_integration' => {'cmd' => "ulimit -t 5\n%l<exe> Numerical_integration%l<ext>"},
    'Percolation_Mean_cluster_density' => {'cmd' => "ulimit -t 10\n%l<exe> Percolation_Mean_cluster_density%l<ext>"},
    'Prime_conspiracy' => {'cmd' => "ulimit -t 10\n%l<exe> Prime_conspiracy%l<ext>"},
    'Primes_-_allocate_descendants_to_their_ancestors' => {'cmd' => "ulimit -t 10\n%l<exe> Primes_-_allocate_descendants_to_their_ancestors%l<ext>"},
    'Primorial_numbers' => {'cmd' => "ulimit -t 10\n%l<exe> Primorial_numbers%l<ext>"},
    'Pythagorean_quadruples' => {'cmd' => "ulimit -t 10\n%l<exe> Pythagorean_quadruples%l<ext>"},
    'Self-describing_numbers' => {'cmd' => "ulimit -t 10\n%l<exe> Self-describing_numbers%l<ext>"},
    'Subset_sum_problem' => {'cmd' => "ulimit -t 8\n%l<exe> Subset_sum_problem%l<ext>"},
    'Sudoku1' => {'cmd' => "ulimit -t 15\n%l<exe> Sudoku1%l<ext>"},
    'Topswops' => {'cmd' => "ulimit -t 10\n%l<exe> Topswops%l<ext>"},
    'Total_circles_area' => {'cmd' => "ulimit -t 10\n%l<exe> Total_circles_area%l<ext>"},
    'Rosetta_Code_Count_examples' => {'skip' => 'long & tested often'},
    'Rosetta_Code_List_authors_of_task_descriptions' => {'skip' => 'long & tested often'},
    'Rosetta_Code_Run_examples' => {'skip' => 'it\'s this task!'},
    'Rot-13' => {cmd => "echo 'Rosetta Code' | %l<exe> Rot-13%l<ext>"},
    'Nautical_bell' => {'skip' => 'long (24 hours)'},
    'Self-referential_sequence' => {'cmd' => "ulimit -t 10\n%l<exe> Self-referential_sequence%l<ext>"},
    'Rosetta_Code_Tasks_without_examples' => {'skip' => 'long, net connection'},
    'Assertions1' => {'skip' => 'macros NYI'},
    'Create_a_file_on_magnetic_tape' => {'skip' => 'need a tape device attached'},
    'Emirp_primes' => {'cmd' => ["%l<exe> Emirp_primes%l<ext> 1 20 \n","%l<exe> Emirp_primes%l<ext> 7700 8000 values\n"]},
    'File_modification_time' => {'cmd' => "%l<exe> File_modification_time%l<ext> File_modification_time%l<ext>"},
    'Function_frequency' => {'cmd' => "%l<exe> Function_frequency%l<ext> Function_frequency%l<ext>"},
    'Lucky_and_even_lucky_numbers' => {
        'cmd' => ["%l<exe> Lucky_and_even_lucky_numbers%l<ext> 20 , lucky\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 1 20\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 1 20 evenlucky\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 6000 -6100\n",
                  "%l<exe> Lucky_and_even_lucky_numbers%l<ext> 6000 -6100 evenlucky\n"]
    },
    'Odd_word_problem' => {'cmd' => ["echo 'we,are;not,in,kansas;any,more.' | %l<exe> Odd_word_problem%l<ext>\n",
                                     "echo 'what,is,the;meaning,of:life.' | %l<exe> Odd_word_problem%l<ext>\n"]
    },
    'Remove_lines_from_a_file' => {'cmd' => ["cal > foo\n","cat foo\n","%l<exe> Remove_lines_from_a_file%l<ext> foo 1 2\n","cat foo"]},
    'Truncate_a_file' => {'cmd' => ["cal > foo\n","cat foo\n","%l<exe> Truncate_a_file%l<ext> foo 69\n","cat foo"]},
    'Executable_library1' => {'skip' => 'need to install library'},
    'Parametrized_SQL_statement' => {'skip' => 'needs a database'},
    'File_input_output0' => {'cmd' => ["cal > input.txt\n","%l<exe> File_input_output0%l<ext>"]},
    'File_input_output1' => {'cmd' => ["cal > input.txt\n","%l<exe> File_input_output1%l<ext>"]},
    'Read_a_file_line_by_line0' => {'cmd' => ["cal > test.txt\n","%l<exe> Read_a_file_line_by_line0%l<ext>"]},
    'Read_a_file_line_by_line1' => {'cmd' => ["cal > test.txt\n","%l<exe> Read_a_file_line_by_line1%l<ext>"]},
    'Take_notes_on_the_command_line' => {'file' => 'notes.txt'},
    'Strip_comments_from_a_string' => {'file' => 'comments.txt','cmd' => ["cat comments.txt\n","%l<exe> Strip_comments_from_a_string%l<ext> < comments.txt"]},
    'A_B0' => { cmd => "echo '13 9' | %l<exe> A_B0%l<ext>" },
    'A_B1' => { cmd => "echo '13 9' | %l<exe> A_B1%l<ext>" },
    'A_B2' => { cmd => "echo '13 9' | %l<exe> A_B2%l<ext>" },
    'Abbreviations__automatic' => {'file' => 'DoWAKA.txt'},
    'Align_columns1' => {'file' => 'Align_columns1.txt', 'cmd' => "%l<exe> Align_columns1%l<ext> left Align_columns1.txt"},
    'Base64_encode_data' => { 'file' => 'favicon.ico' },
    'CSV_data_manipulation0' => {'file' => 'whatever.csv'},
    'CSV_data_manipulation1' => {'skip' => 'fragment'},
    'Compiler_lexical_analyzer' => {'file' => 'test-case-3.txt','cmd' => "%l<exe> Compiler_lexical_analyzer%l<ext> test-case-3.txt"},
    'Delete_a_file' => {'cmd' => ["touch input.txt\n","mkdir docs\n","ls .\n","%l<exe> Delete_a_file%l<ext>\n","ls .\n"]},
    'I_before_E_except_after_C1' => {'file' => '1_2_all_freq.txt'},
    'Markov_chain_text_generator' => {'file' => 'alice_oz.txt','cmd' => "%l<exe> Markov_chain_text_generator%l<ext> < alice_oz.txt --n=3 --words=200"},
    'Read_a_configuration_file' => {'file' => 'file.cfg','cmd' => ["cat file.cfg\n", "%l<exe> Read_a_configuration_file%l<ext>"]},
    'Read_a_file_character_by_character_UTF80' => {'file' => 'whatever','cmd' => "cat whatever | %l<exe> Read_a_file_character_by_character_UTF80%l<ext>"},
    'Read_a_file_character_by_character_UTF81' => {'file' => 'whatever','cmd' => "%l<exe> Read_a_file_character_by_character_UTF81%l<ext>"},
    'Read_a_specific_line_from_a_file' => {'cmd' => ["cal 2018 > cal.txt\n", "%l<exe> Read_a_specific_line_from_a_file%l<ext> cal.txt"]},
    'Rename_a_file' => {'cmd' => ["touch input.txt\n", "mkdir docs\n", "%l<exe> Rename_a_file%l<ext>\n", "ls ."]},
    'Selective_File_Copy' => {'file' => 'sfc.dat'},
    'Self-hosting_compiler' => {'cmd' => "echo 'say 'hello World!' | %l<exe> Self-hosting_compiler%l<ext>"},
    'Separate_the_house_number_from_the_street_name' => {'file' => 'addresses.txt',
        'cmd' => "cat addresses.txt | %l<exe> Separate_the_house_number_from_the_street_name%l<ext>"
    },
    'Synchronous_concurrency' => {'cmd' => ["cal 2018 > cal.txt\n","%l<exe> Synchronous_concurrency%l<ext> cal.txt"]},
    'Text_processing_1' => {'file' => 'readings.txt', 'cmd' => "%l<exe> Text_processing_1%l<ext> < readings.txt"},
    'Text_processing_2' => {'file' => 'readings.txt', 'cmd' => "%l<exe> Text_processing_2%l<ext> < readings.txt"},
    'Text_processing_Max_licenses_in_use' => {'file' => 'mlijobs.txt',
        'cmd' => "%l<exe> Text_processing_Max_licenses_in_use%l<ext> < mlijobs.txt"
    },
    'Update_a_configuration_file' => {'file' => 'test.cfg',
        'cmd' => ["%l<exe> Update_a_configuration_file%l<ext> --/needspeeling --seedsremoved --numberofbananas=1024 --numberofstrawberries=62000 test.cfg\n",
                  "cat test.cfg\n"]
    },
    'Word_count' => {'file' => 'lemiz.txt', 'cmd' => "%l<exe> Word_count%l<ext> lemiz.txt 10"},
    'Zhang-Suen_thinning_algorithm' => {'file' => 'rc-image.txt','cmd' => "%l<exe> Zhang-Suen_thinning_algorithm%l<ext> rc-image.txt"},
    'I_before_E_except_after_C0' => {'file' => 'unixdict.txt'},
    'Stream_Merge' => {'skip' => 'needs input files'},
    'Ordered_words' => {'file' => 'unixdict.txt','cmd' => "%l<exe> Ordered_words%l<ext> < unixdict.txt"},
    'User_defined_pipe_and_redirection_operators' => {'file' => 'List_of_computer_scientists.lst'},
    'Letter_frequency' => {'file' => 'List_of_computer_scientists.lst',
         'cmd' => "cat List_of_computer_scientists.lst | %l<exe> Letter_frequency%l<ext>"
     },
    'Hello_world_Line_printer0' => {'skip' => 'needs line printer attached'},
    'Hello_world_Line_printer1' => {'skip' => 'needs line printer attached'},
    'Narcissist' => {'skip' => 'needs to run from command line'},
    'Anagrams0' => {'file' => 'unixdict.txt'},
    'Anagrams1' => {'file' => 'unixdict.txt'},
    'Anagrams_Deranged_anagrams' => {'file' => 'unixdict.txt'},
    'Semordnilap' => {'file' => 'unixdict.txt'},
    'Textonyms' => {'file' => 'unixdict.txt'},
    'Handle_a_signal' => {'skip' => 'needs user intervention'},
    'Copy_a_string2' => {'skip' => 'nyi'},
    'Flow-control_structures' => {'skip' => 'nyi'},
    'Arena_storage_pool' => {'skip' => 'ok to skip; no code'},
    'Aspect_Oriented_Programming' => {'skip' => 'ok to skip; no code'},
    'Check_output_device_is_a_terminal' => {'skip' => 'ok to skip; no code'},
    'Command-line_arguments' => {'skip' => 'ok to skip; no code'},
    'Hello_world_Newbie' => {'skip' => 'ok to skip; no code'},
    'Naming_conventions' => {'skip' => 'ok to skip; no code'},
    'Operator_precedence' => {'skip' => 'ok to skip; no code'},
    'Random_number_generator__included_' => {'skip' => 'ok to skip; no code'},
    'Shell_one_liner' => {'skip' => 'ok to skip; no code'},
    'Special_characters' => {'skip' => 'ok to skip; no code'},
    'Table_creation' => {'skip' => 'ok to skip; no code'},
    'Variable_size_Set' => {'skip' => 'ok to skip; no code'},
    'Atomic_updates' => {'cmd' => "ulimit -t 10\n%l<exe> Atomic_updates%l<ext>\n"},
    'Birthday_problem1' => {'cmd' => "ulimit -t 5\n%l<exe> Birthday_problem1%l<ext>\n"},
    'Count_in_factors0' => {'cmd' => "ulimit -t 1\n%l<exe> Count_in_factors0%l<ext>\n"},
    'Count_in_octal' => {'cmd' => "ulimit -t 1\n%l<exe> Count_in_octal%l<ext>\n"},
    'Draw_a_clock' => {'cmd' => "ulimit -t 1\n%l<exe> Draw_a_clock%l<ext>\n"},
    'Echo_server0' => {'skip' => 'runs forever'},
    'Echo_server1' => {'skip' => 'runs forever'},
    'Chat_server' => {'skip' => 'runs forever'},
    'Elementary_cellular_automaton_Infinite_length' => {'cmd' => "ulimit -t 2\n%l<exe> Elementary_cellular_automaton_Infinite_length%l<ext>\n"},
    'Find_limit_of_recursion' => {'cmd' => "ulimit -t 6\n%l<exe> Find_limit_of_recursion%l<ext>\n"},
    'Forest_fire' => {'cmd' => ["ulimit -t 20\n%l<exe> Forest_fire%l<ext>\n","%l<exe> -e'print \"\e[0m\ \e[H\e[2J\"'"]},
    'Fractran1' => {'cmd' => "ulimit -t 10\n%l<exe> Fractran1%l<ext>\n"},
    'Integer_sequence' => {'cmd' => "ulimit -t 1\n%l<exe> Integer_sequence%l<ext>\n"},
    'Linux_CPU_utilization' => {'skip' => 'takes forever to time out', 'cmd' => "ulimit -t 1\n%l<exe> Linux_CPU_utilization%l<ext>\n"},
    'Loops_Infinite0' => {'cmd' => "ulimit -t 1\n%l<exe> Loops_Infinite0%l<ext>\n"},
    'Loops_Infinite1' => {'cmd' => "ulimit -t 1\n%l<exe> Loops_Infinite1%l<ext>\n"},
    'Pi' => {'cmd' => "ulimit -t 5\n%l<exe> Pi%l<ext>\n"},
    'Pythagorean_triples1' => {'cmd' => "ulimit -t 1\n%l<exe> Pythagorean_triples1%l<ext>\n"},
    'Pythagorean_triples2' => {'cmd' => "ulimit -t 8\n%l<exe> Pythagorean_triples2%l<ext>\n"},
    'Pythagorean_triples3' => {'cmd' => "ulimit -t 8\n%l<exe> Pythagorean_triples3%l<ext>\n"},
    'Wireworld' => {'cmd' => "%l<exe> Wireworld%l<ext> --stop-on-repeat"},
    'Memory_layout_of_a_data_structure0' => {'skip' => 'speculation'},
    'Memory_layout_of_a_data_structure1' => {'skip' => 'speculation'},
    'Loop_over_multiple_arrays_simultaneously3' => {'skip' => 'stub'},
    'Loop_over_multiple_arrays_simultaneously4' => {'skip' => 'stub'},
    'Conditional_structures1' => {'skip' => 'user input'},
    'Create_a_two-dimensional_array_at_runtime0' => {'cmd' => "echo \"5x35\n\" | %l<exe> Create_a_two-dimensional_array_at_runtime0%l<ext>"},
    'Create_a_two-dimensional_array_at_runtime1' => {'cmd' => "echo \"3x10\n\" | %l<exe> Create_a_two-dimensional_array_at_runtime1%l<ext>"},
    'Arithmetic_Integer' => {'cmd' => "echo \"27\n31\n\" | %l<exe> Arithmetic_Integer%l<ext>"},
    'Balanced_brackets0' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets0%l<ext>"},
    'Balanced_brackets1' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets1%l<ext>"},
    'Balanced_brackets2' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets2%l<ext>"},
    'Balanced_brackets3' => {'cmd' => "echo \"22\n\" | %l<exe> Balanced_brackets3%l<ext>"},
    'Decision_tables' => {'skip' => 'user interaction'},
    'Dynamic_variable_names' => {'cmd' => "echo \"this-var\" | %l<exe> Dynamic_variable_names%l<ext>"},
    'Execute_HQ9_1' => {'skip' => 'user interaction'},
    'File_size_distribution' => {'cmd' => "%l<exe> File_size_distribution%l<ext> '~'"},
    'Hello_world_Graphical' => {'skip' => 'user interaction, gui'},
    'Hello_world_Web_server' => {'skip' => 'user interaction, gui'},
    'Horizontal_sundial_calculations' => {'cmd' => "echo \"-4.95\n-150.5\n-150\n\" | %l<exe> Horizontal_sundial_calculations%l<ext>"},
    'Input_Output_for_Lines_of_Text0' => {
        'cmd' => "echo \"3\nhello\nhello world\nPack my Box with 5 dozen liquor jugs\" | %l<exe> Input_Output_for_Lines_of_Text0%l<ext>"
    },
    'Input_Output_for_Lines_of_Text1' => {
        'cmd' => "echo \"3\nhello\nhello world\nPack my Box with 5 dozen liquor jugs\" | %l<exe> Input_Output_for_Lines_of_Text1%l<ext>"
    },
    'Input_Output_for_Pairs_of_Numbers' => {
        'cmd' => "echo \"5\n1 2\n10 20\n-3 5\n100 2\n5 5\" | %l<exe> Input_Output_for_Pairs_of_Numbers%l<ext>"
    },
    'Reverse_words_in_a_string' => { 'file' => 'reverse.txt','cmd' => "%l<exe> Reverse_words_in_a_string%l<ext> reverse.txt"},
    'Rosetta_Code_Find_bare_lang_tags' => {'file' => 'rcpage','cmd' => "%l<exe> Rosetta_Code_Find_bare_lang_tags%l<ext> rcpage"},
    'Rosetta_Code_Fix_code_tags' => {'file' => 'rcpage','cmd' => "%l<exe> Rosetta_Code_Fix_code_tags%l<ext> rcpage"},
    'Integer_comparison0' => {'cmd' => "echo \"9\n17\" | %l<exe> Integer_comparison0%l<ext>"},
    'Integer_comparison2' => {'cmd' => "echo \"9\n17\" | %l<exe> Integer_comparison2%l<ext>"},
    'Inverted_index' => {'file' => 'unixdict.txt','cmd' => "echo \"rosetta\ncode\nblargg\n\" | %l<exe> Inverted_index%l<ext> unixdict.txt\n"},
    'Keyboard_input_Obtain_a_Y_or_N_response' => {'skip' => 'user interaction, custom shell'},
    'Keyboard_macros' => {'skip' => 'user interaction, custom shell'},
    'Longest_string_challenge' => {'cmd' => "echo \"a\nbb\nccc\nddd\nee\nf\nggg\n\" | %l<exe> Longest_string_challenge%l<ext>\n"},
    'Magic_squares_of_doubly_even_order' => {'cmd' => "%l<exe> Magic_squares_of_doubly_even_order%l<ext> 12"},
    'Magic_squares_of_singly_even_order' => {'cmd' => "%l<exe> Magic_squares_of_singly_even_order%l<ext> 10"},
    'Magic_squares_of_odd_order' => {'cmd' => "%l<exe> Magic_squares_of_odd_order%l<ext> 11"},
    'Menu' => {'cmd' => "echo \"2\n\" | %l<exe> Menu%l<ext>\n"},
    'Morse_code' => {'cmd' => "echo \"Howdy, World!\n\" | %l<exe> Morse_code%l<ext>\n"},
    'Number_names0' => {'skip' => 'user interaction'},
    'One-time_pad0' => {'skip' => 'user interaction, manual intervention'},
    'One-time_pad1' => {'skip' => 'user interaction, manual intervention'},
    'Price_fraction0' => {'cmd' => "echo \".86\" | %l<exe> Price_fraction0%l<ext>\n"},
    'Price_fraction1' => {'cmd' => "echo \".74\" | %l<exe> Price_fraction1%l<ext>\n"},
    'Price_fraction2' => {'cmd' => "echo \".35\" | %l<exe> Price_fraction2%l<ext>\n"},
    'Simple_windowed_application' => {'skip' => 'user interaction, gui'},
    'Sleep' => {'cmd' => "echo \"3.86\" | %l<exe> Sleep%l<ext>\n"},
    'Sparkline_in_unicode' => {
        'cmd' => ["echo \"9 18 27 36 45 54 63 72 63 54 45 36 27 18 9\" | %l<exe> Sparkline_in_unicode%l<ext>\n",
                  "echo \"1.5, 0.5 3.5, 2.5 5.5, 4.5 7.5, 6.5\" | %l<exe> Sparkline_in_unicode%l<ext>\n",
                  "echo \"3 2 1 0 -1 -2 -3 -4 -3 -2 -1 0 1 2 3\" | %l<exe> Sparkline_in_unicode%l<ext>\n"]
    },
    'Temperature_conversion0' => {'cmd' => "echo \"21\" | %l<exe> Temperature_conversion0%l<ext>\n"},
    'Temperature_conversion1' => {
        'cmd' => ["echo \"0\" | %l<exe> Temperature_conversion1%l<ext>\n",
                  "echo \"0c\" | %l<exe> Temperature_conversion1%l<ext>\n",
                  "echo \"212f\" | %l<exe> Temperature_conversion1%l<ext>\n",
                  "echo \"-40c\" | %l<exe> Temperature_conversion1%l<ext>\n"]
    },
    'Trabb_Pardo_Knuth_algorithm' => {'cmd' => "echo \"10 -1 1 2 3 4 4.3 4.305 4.303 4.302 4.301\" | %l<exe> Trabb_Pardo_Knuth_algorithm%l<ext>\n"},
    'Truth_table' => {
        'cmd' => ["%l<exe> Truth_table%l<ext> 'A ^ B'\n",
                  "%l<exe> Truth_table%l<ext> 'foo & bar | baz'\n",
                  "%l<exe> Truth_table%l<ext> 'Jim & (Spock ^ Bones) | Scotty'\n"]
    },
    'User_input_Graphical' => {'skip' => 'user interaction, gui'},
    'User_input_Text' => { 'cmd' => "echo \"Rosettacode\n10\" %l<exe> User_input_Text%l<ext> "},
    'Window_creation' => {'skip' => 'user interaction, gui'},

# games
    '15_Puzzle_Game' => {'skip' => 'user interaction, game'},
    '2048' => {'skip' => 'user interaction, game'},
    '24_game' => {'skip' => 'user interaction, game'},
    '24_game_Solve' => {'skip' => 'user interaction, game'},
    'Bulls_and_cows' => {'skip' => 'user interaction, game'},
    'Bulls_and_cows_Player' => {'skip' => 'user interaction, game'},
    'Flipping_bits_game' => {'skip' => 'user interaction, game'},
    'Guess_the_number' => {'skip' => 'user interaction, game'},
    'Guess_the_number_With_feedback' => {'skip' => 'user interaction, game'},
    'Guess_the_number_With_feedback__player_' => {'skip' => 'user interaction, game'},
    'Go_Fish' => {'skip' => 'user interaction, game'},
    'Hunt_The_Wumpus' => {'skip' => 'user interaction, game'},
    'Mad_Libs' => {'skip' => 'user interaction, game'},
    'Mastermind' => {'skip' => 'user interaction, game'},
    'Minesweeper_game' => {'skip' => 'user interaction, game'},
    'Number_reversal_game' => {'skip' => 'user interaction, game'},
    'Penney_s_game' => {'skip' => 'user interaction, game'},
    'Pig_the_dice_game' => {'skip' => 'user interaction, game'},
    'RCRPG' => {'skip' => 'user interaction, game'},
    'Rock-paper-scissors0' => {'skip' => 'user interaction, game'},
    'Snake' => {'skip' => 'user interaction, game'},
    'Snake_And_Ladder' => {'skip' => 'user interaction, game'},
    'Tic-tac-toe' => {'skip' => 'user interaction, game'},

# image producing tasks
    'Dragon_curve' => { 'cmd' => ["%l<exe> Dragon_curve%l<ext> > Dragon-curve-perl6.svg\n","$view Dragon-curve-perl6.svg"]},
    'Koch_curve0' => { 'cmd' => ["%l<exe> Koch_curve0%l<ext> > Koch_curve0-perl6.svg\n","$view Koch_curve0-perl6.svg"]},
    'Koch_curve1' => { 'cmd' => ["%l<exe> Koch_curve1%l<ext> > Koch_curve1-perl6.svg\n","$view Koch_curve1-perl6.svg"]},
    'Bitmap_B_zier_curves_Cubic' => { 'cmd' => ["%l<exe> Bitmap_B_zier_curves_Cubic%l<ext> > Bezier-cubic-perl6.ppm\n","$view Bezier-cubic-perl6.ppm"]},
    'Bitmap_B_zier_curves_Quadratic' => { 'cmd' => ["%l<exe> Bitmap_B_zier_curves_Quadratic%l<ext> > Bezier-quadratic-perl6.ppm\n","$view Bezier-quadratic-perl6.ppm"]},
    'Bitmap_Write_a_PPM_file' => { 'cmd' => ["%l<exe> Bitmap_Write_a_PPM_file%l<ext> > Bitmap-write-ppm-perl6.ppm\n","$view Bitmap-write-ppm-perl6.ppm"]},
    'Fractal_tree'  => { 'cmd' => ["%l<exe> Fractal_tree%l<ext> > Fractal-tree-perl6.svg\n","$view Fractal-tree-perl6.svg"]},
    'Plot_coordinate_pairs' => { 'cmd' => ["%l<exe> Plot_coordinate_pairs%l<ext> > Plot-coordinate-pairs-perl6.svg\n","$view Plot-coordinate-pairs-perl6.svg"]},
    'Pythagoras_tree' => { 'cmd' => ["%l<exe> Pythagoras_tree%l<ext> > Pythagoras-tree-perl6.svg\n","$view Pythagoras-tree-perl6.svg"]},
    'Pentagram' => { 'cmd' => ["%l<exe> Pentagram%l<ext> > Pentagram-perl6.svg\n","$view Pentagram-perl6.svg"]},
    'Sierpinski_triangle_Graphical' => { 'cmd' => ["%l<exe> Sierpinski_triangle_Graphical%l<ext> > Sierpinski_triangle_Graphical-perl6.svg\n","$view Sierpinski_triangle_Graphical-perl6.svg"]},
    'Yin_and_yang0' => { 'cmd' => ["%l<exe> Yin_and_yang0%l<ext> > Yin_and_yang-perl6.svg\n","$view Yin_and_yang-perl6.svg"]},
    'Sierpinski_pentagon' => { 'cmd' => ["%l<exe> Sierpinski_pentagon%l<ext> > Sierpinski_pentagon-perl6.svg\n","$view Sierpinski_pentagon-perl6.svg"]},
    'Superellipse' => { 'cmd' => ["%l<exe> Superellipse%l<ext> > Superellipse-perl6.svg\n","$view Superellipse-perl6.svg"]},
    'Mandelbrot_set' => { 'cmd' => ["%l<exe> Mandelbrot_set%l<ext> 255 > Mandelbrot-set-perl6.ppm\n","$view Mandelbrot-set-perl6.ppm"]},
    'Bitmap_Histogram' => {'file' => 'Lenna.ppm', 'cmd' => ["%l<exe> Bitmap_Histogram%l<ext>\n","$view Lenna-bw.pbm"]},
    'Bitmap_Read_a_PPM_file' => {'file' => 'camelia.ppm', 'cmd' => ["%l<exe> Bitmap_Read_a_PPM_file%l<ext>\n","$view camelia-gs.pgm"]},
    'Bitmap_Read_an_image_through_a_pipe' => {'file' => 'camelia.png', 'cmd' => ["%l<exe> Bitmap_Read_an_image_through_a_pipe%l<ext>\n","$view camelia.ppm"]},
    'Grayscale_image' => {'file' => 'default.ppm', 'cmd' => ["%l<exe> Grayscale_image%l<ext>\n","$view default.pgm"]},
    'Draw_a_sphere' => { 'cmd' => ["%l<exe> Draw_a_sphere%l<ext>\n","$view sphere-perl6.pgm"]},
    'Death_Star' => { 'cmd' => ["%l<exe> Death_Star%l<ext>\n","$view deathstar-perl6.pgm"]},
    'Archimedean_spiral' => {'cmd' => ["%l<exe> Archimedean_spiral%l<ext>\n","$view Archimedean-spiral-perl6.png"]},
    'Julia_set' => {'cmd' => ["%l<exe> Julia_set%l<ext>\n","$view Julia-set-perl6.png"]},
    'Chaos_game' => {'cmd' => ["%l<exe> Chaos_game%l<ext>\n","$view Chaos-game-perl6.png"]},
    'Color_wheel' => {'cmd' => ["%l<exe> Color_wheel%l<ext>\n","$view Color-wheel-perl6.png"]},
    'Barnsley_fern' => {'cmd' => ["%l<exe> Barnsley_fern%l<ext>\n","$view Barnsley-fern-perl6.png"]},
    'Voronoi_diagram' => {
        'cmd' => ["%l<exe> Voronoi_diagram%l<ext>\n",
                  "$view Voronoi-Minkowski-perl6.png",
                  "$view Voronoi-Taxicab-perl6.png",
                  "$view Voronoi-Euclidean-perl6.png",
                 ]
    },
    'Kronecker_product_based_fractals' => {
        'cmd' => ["%l<exe> Kronecker_product_based_fractals%l<ext>\n",
                  "$view kronecker-vicsek-perl6.png",
                  "$view kronecker-carpet-perl6.png",
                  "$view kronecker-six-perl6.png",
                 ]
    },
    'Munching_squares0' => {'cmd' => ["%l<exe> Munching_squares0%l<ext>\n","$view munching0.ppm"]},
    'Munching_squares1' => {'cmd' => ["%l<exe> Munching_squares1%l<ext>\n","$view munching1.ppm"]},
    'Pinstripe_Display' => {'cmd' => ["%l<exe> Pinstripe_Display%l<ext>\n","$view pinstripes.pgm"]},
    'Plasma_effect' => {'cmd' => ["%l<exe> Plasma_effect%l<ext>\n","$view Plasma-perl6.png"]},
) }

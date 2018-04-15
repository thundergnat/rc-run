use HTTP::UserAgent;
use URI::Escape;
use JSON::Fast;
use Sort::Naturally;
use MONKEY-SEE-NO-EVAL;

my $client   = HTTP::UserAgent.new;
my $url      = 'http://rosettacode.org/mw';

my $lang     = 'Perl_6';   # language
my $exe      = 'perl6';    # executable to run perl6 in a shell
my $view     = 'xdg-open'; #imager viewer, this will open default
my %resource = load-resources();
my $download = True;

my @tasks;

run('clear');
note 'Retreiving tasks';

if @*ARGS {
    @tasks = |@*ARGS;
    $download = False;
}

if $download {
    @tasks = mediawiki-query(
    $url, 'pages',
    :generator<categorymembers>,
    :gcmtitle("Category:$lang"),
    :gcmlimit<350>,
    :rawcontinue(),
    :prop<title>
    )»<title>.grep( * !~~ /^'Category:'/ );
}

for @tasks -> $title {
    # If you want to resume partially into automatic
    # downloads, adjust $skip to skip that many tasks
    my $skip = 0;
    next if $++ < $skip;
    note "Skipping first $skip tasks..." if $skip;
    next unless $title ~~ /\S/; # filter blank lines
    say $skip + ++$, " $title";

    my $page = $client.get("{ $url }/index.php?title={ uri-escape $title }&action=raw").content;
    say "Whoops, can't find page: $url/$title :check spelling." and next if $page.elems == 0;
    say "Getting code from: http://rosettacode.org/wiki/{ $title.subst(' ', '_', :g) }#Perl_6";

    my $perl6 = $page.comb(/'=={{header|Perl 6}}==' .+? [<?before \n'=='<-[={]>*'{{header'> || $] /).Str // whoops;

    if $perl6 ~~ /^^ 'See [[' (.+?) '/Perl_6' / {
        $perl6 = $client.get("{ $url }/index.php?title={ uri-escape $/[0].Str ~ '/Perl_6' }&action=raw").content;
    }

    my $name = $title.subst(/<-[0..9A..Za..z]>/, '_', :g);

    my $dir = mkdir "./rc/$name";

    spurt( "./rc/$name/$name.txt", $perl6 );

    my @blocks = $perl6.comb(/<?after '<lang perl6>'> .*? <?before '</lang>'> /);

    for @blocks.kv -> $k, $v {
        my $n = $k > 0 ?? $k !! '';
        spurt( "./rc/$name/$name$n.p6", $v );
        say "Skipping $name$n: ", %resource{"$name$n"}<skip>, "\n"
          and next if %resource{"$name$n"}<skip>;
        say "\nTesting $name$n";
        run-it($name, "$name$n");
    }
    say '=' x 79;
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
    chdir "./rc/$dir/";
    if %resource{$code}<file> -> $fn {
        copy "./../resources/{$fn}", "./{$fn}"
    }
    my @cmd = %resource{$code}<cmd> ?? |%resource{$code}<cmd> !! "$exe $code.p6";
    for @cmd -> $cmd {
        say "\nCommand line: $cmd";
        try EVAL(shell $cmd);
    }
    chdir $current;
    say "\nDone $code";
}

sub uri-query-string (*%fields) { %fields.map({ "{.key}={uri-escape .value}" }).join('&') }

sub clear { "\r" ~ ' ' x 100 ~ "\r" }

sub whoops { note "{'#' x 79}\n\nNo code found\nMay be bad markup\n\n{'#' x 79}"; '' }

sub load-resources {
    (
    'Amb1' => {'skip' => 'broken'},
    'Amb2' => {'skip' => 'broken'},
    'Formal_power_series' => {'skip' => 'broken'},
    'Multiline_shebang' => {'skip' => 'broken'},
    'Names_to_numbers' => {'skip' => 'broken'},
    'Set_of_real_numbers' => {'skip' => 'broken'},
    'Singly_linked_list_Element_insertion' => {'skip' => 'broken'},
    'Sorting_algorithms_Strand_sort' => {'skip' => 'broken'},
    'Window_creation_X11' => {'skip' => 'broken'},
    'Modular_arithmetic' => {'skip' => 'broken (module wont install, pull request pending)'},
    'FTP' => {'skip' => 'broken module'},
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
    'CSV_data_manipulation1' => {'skip' => 'fragment'},
    'Doubly_linked_list_Traversal' => {'skip' => 'fragment'},
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
    'Rot_13' => {'skip' => 'fragment'},
    'Scope_modifiers0' => {'skip' => 'fragment'},
    'Singly_linked_list_Element_definition' => {'skip' => 'fragment'},
    'Sort_a_list_of_object_identifiers1' => {'skip' => 'fragment'},
    'Sort_a_list_of_object_identifiers2' => {'skip' => 'fragment'},
    'Sort_an_integer_array0' => {'skip' => 'fragment'},
    'Sort_an_integer_array1' => {'skip' => 'fragment'},
    'Special_variables0' => {'skip' => 'fragment'},
    'Special_variables1' => {'skip' => 'fragment'},
    'Special_variables2' => {'skip' => 'fragment'},
    'Spiral_matrix1' => {'skip' => 'fragment'},
    'Stack' => {'skip' => 'fragment'},
    'Stair_climbing_puzzle' => {'skip' => 'fragment'},
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
    '9_billion_names_of_God_the_integer' => {'cmd' => "ulimit -t 10\n$exe 9_billion_names_of_God_the_integer.p6"},
    'Arithmetic_Rational0' => {'cmd' => "ulimit -t 10\n$exe Arithmetic_Rational0.p6"},
    'Dining_philosophers' => {'cmd' => "ulimit -t 1\n$exe Dining_philosophers.p6"},
    'Find_largest_left_truncatable_prime_in_a_given_base' => {'cmd' => "ulimit -t 15\n$exe Find_largest_left_truncatable_prime_in_a_given_base.p6"},
    'Four_is_the_number_of_letters_in_the____' => {'cmd' => "ulimit -t 13\n$exe Four_is_the_number_of_letters_in_the____.p6"},
    'Iterated_digits_squaring0' => {'cmd' => "ulimit -t 5\n$exe Iterated_digits_squaring0.p6"},
    'Iterated_digits_squaring1' => {'cmd' => "ulimit -t 5\n$exe Iterated_digits_squaring1.p6"},
    'Iterated_digits_squaring2' => {'cmd' => "ulimit -t 5\n$exe Iterated_digits_squaring2.p6"},
    'Kaprekar_numbers1' => {'cmd' => "ulimit -t 2\n$exe Kaprekar_numbers1.p6"},
    'Kaprekar_numbers2' => {'cmd' => "ulimit -t 2\n$exe Kaprekar_numbers2.p6"},
    'Knapsack_problem_0_1' => {'cmd' => "ulimit -t 10\n$exe Knapsack_problem_0_1.p6"},
    'Knapsack_problem_Bounded' => {'cmd' => "ulimit -t 10\n$exe Knapsack_problem_Bounded.p6"},
    'Last_letter_first_letter' => {'cmd' => "ulimit -t 15\n$exe Last_letter_first_letter.p6"},
    'Left_factorials0' => {'cmd' => "ulimit -t 10\n$exe Left_factorials0.p6"},
    'Lucas_Lehmer_test' => {'cmd' => "ulimit -t 10\n$exe Lucas_Lehmer_test.p6"},
    'Lychrel_numbers' => {'cmd' => "ulimit -t 10\n$exe Lychrel_numbers.p6"},
    'Metronome' => {'skip' => 'long'},
    'Multiple_regression' => {'cmd' => "ulimit -t 10\n$exe Multiple_regression.p6"},
    'Narcissistic_decimal_number0' => {'cmd' => "ulimit -t 10\n$exe Narcissistic_decimal_number0.p6"},
    'Narcissistic_decimal_number1' => {'cmd' => "ulimit -t 10\n$exe Narcissistic_decimal_number1.p6"},
    'Numerical_integration' => {'cmd' => "ulimit -t 5\n$exe Numerical_integration.p6"},
    'Percolation_Mean_cluster_density' => {'cmd' => "ulimit -t 10\n$exe Percolation_Mean_cluster_density.p6"},
    'Prime_conspiracy' => {'cmd' => "ulimit -t 10\n$exe Prime_conspiracy.p6"},
    'Primes___allocate_descendants_to_their_ancestors' => {'cmd' => "ulimit -t 10\n$exe Primes___allocate_descendants_to_their_ancestors.p6"},
    'Primorial_numbers' => {'cmd' => "ulimit -t 10\n$exe Primorial_numbers.p6"},
    'Pythagorean_quadruples' => {'cmd' => "ulimit -t 10\n$exe Pythagorean_quadruples.p6"},
    'Self_describing_numbers' => {'cmd' => "ulimit -t 10\n$exe Self_describing_numbers.p6"},
    'Subset_sum_problem' => {'cmd' => "ulimit -t 8\n$exe Subset_sum_problem.p6"},
    'Sudoku1' => {'cmd' => "ulimit -t 15\n$exe Sudoku1.p6"},
    'Topswops' => {'cmd' => "ulimit -t 10\n$exe Topswops.p6"},
    'Total_circles_area' => {'cmd' => "ulimit -t 10\n$exe Total_circles_area.p6"},
    'Rosetta_Code_Count_examples' => {'skip' => 'long & tested often'},
    'Rosetta_Code_List_authors_of_task_descriptions' => {'skip' => 'long & tested often'},
    'Rosetta_Code_Run_examples' => {'skip' => 'it\'s this task!'},
    'Nautical_bell' => {'skip' => 'long (24 hours)'},
    'Self_referential_sequence' => {'cmd' => "ulimit -t 10\n$exe Self_referential_sequence.p6"},
    'Rosetta_Code_Tasks_without_examples' => {'skip' => 'long, net connection'},
    'Assertions1' => {'skip' => 'macros NYI'},
    'Create_a_file_on_magnetic_tape' => {'skip' => 'need a tape device attached'},
    'Emirp_primes' => {'cmd' => ["$exe Emirp_primes.p6 1 20 \n","$exe Emirp_primes.p6 7700 8000 values\n"]},
    'File_modification_time' => {'cmd' => "$exe File_modification_time.p6 File_modification_time.p6"},
    'Function_frequency' => {'cmd' => "$exe Function_frequency.p6 Function_frequency.p6"},
    'Lucky_and_even_lucky_numbers' => {
        'cmd' => ["$exe Lucky_and_even_lucky_numbers.p6 20 , lucky\n",
                  "$exe Lucky_and_even_lucky_numbers.p6 1 20\n",
                  "$exe Lucky_and_even_lucky_numbers.p6 1 20 evenlucky\n",
                  "$exe Lucky_and_even_lucky_numbers.p6 6000 -6100\n",
                  "$exe Lucky_and_even_lucky_numbers.p6 6000 -6100 evenlucky\n"]
    },
    'Odd_word_problem' => {'cmd' => ["echo 'we,are;not,in,kansas;any,more.' | $exe Odd_word_problem.p6\n",
                                     "echo 'what,is,the;meaning,of:life.' | $exe Odd_word_problem.p6\n"]
    },
    'Remove_lines_from_a_file' => {'cmd' => ["cal > foo\n","cat foo\n","$exe Remove_lines_from_a_file.p6 foo 1 2\n","cat foo"]},
    'Truncate_a_file' => {'cmd' => ["cal > foo\n","cat foo\n","$exe Truncate_a_file.p6 foo 69\n","cat foo"]},
    'Executable_library1' => {'skip' => 'need to install library'},
    'Parametrized_SQL_statement' => {'skip' => 'needs a database'},
    'Read_a_file_line_by_line0' => {'cmd' => ["cal > test.txt\n","$exe Read_a_file_line_by_line0.p6"]},
    'Read_a_file_line_by_line1' => {'cmd' => ["cal > test.txt\n","$exe Read_a_file_line_by_line1.p6"]},
    'Take_notes_on_the_command_line' => {'file' => 'notes.txt'},
    'Strip_comments_from_a_string' => {'file' => 'comments.txt','cmd' => ["cat comments.txt\n","$exe Strip_comments_from_a_string.p6 < comments.txt"]},
    'A_B0' => { cmd => "echo '13 9' | $exe A_B0.p6" },
    'A_B1' => { cmd => "echo '13 9' | $exe A_B1.p6" },
    'A_B2' => { cmd => "echo '13 9' | $exe A_B2.p6" },
    'Abbreviations__automatic' => {'file' => 'DoWAKA.txt'},
    'Align_columns1' => {'file' => 'Align_columns1.txt'},
    'Base64_encode_data' => { 'file' => 'favicon.ico' },
    'CSV_data_manipulation0' => {'file' => 'whatever.csv'},
    'CSV_data_manipulation1' => {'file' => 'whatever.csv'},
    'Compiler_lexical_analyzer' => {'file' => 'test-case-3.txt','cmd' => "$exe Compiler_lexical_analyzer.p6 test-case-3.txt"},
    'Delete_a_file' => {'cmd' => ["touch input.txt\n","mkdir docs\n","ls .\n","$exe Delete_a_file.p6\n","ls .\n"]},
    'I_before_E_except_after_C1' => {'file' => '1_2_all_freq.txt'},
    'Markov_chain_text_generator' => {'file' => 'alice_oz.txt','cmd' => "$exe Markov_chain_text_generator.p6 < alice_oz.txt --n=3 --words=200"},
    'Read_a_configuration_file' => {'file' => 'file.cfg','cmd' => ["cat file.cfg\n", "$exe Read_a_configuration_file.p6"]},
    'Read_a_file_character_by_character_UTF80' => {'file' => 'whatever','cmd' => "cat whatever | $exe Read_a_file_character_by_character_UTF80.p6"},
    'Read_a_file_character_by_character_UTF81' => {'file' => 'whatever','cmd' => "$exe Read_a_file_character_by_character_UTF81.p6"},
    'Read_a_specific_line_from_a_file' => {'cmd' => ["cal 2018 > cal.txt\n", "$exe Read_a_specific_line_from_a_file.p6 cal.txt"]},
    'Rename_a_file' => {'cmd' => ["touch input.txt\n", "mkdir docs\n", "$exe Rename_a_file.p6\n", "ls ."]},
    'Selective_File_Copy' => {'file' => 'sfc.dat'},
    'Self_hosting_compiler' => {'cmd' => "echo 'say 'hello World!' | $exe Self_hosting_compiler.p6"},
    'Separate_the_house_number_from_the_street_name' => {'file' => 'addresses.txt',
        'cmd' => "cat addresses.txt | $exe Separate_the_house_number_from_the_street_name.p6"
    },
    'Synchronous_concurrency' => {'cmd' => ["cal 2018 > cal.txt\n","$exe Synchronous_concurrency.p6 cal.txt"]},
    'Text_processing_1' => {'file' => 'readings.txt', 'cmd' => "$exe Text_processing_1.p6 < readings.txt"},
    'Text_processing_2' => {'file' => 'readings.txt', 'cmd' => "$exe Text_processing_2.p6 < readings.txt"},
    'Text_processing_Max_licenses_in_use' => {'file' => 'mlijobs.txt',
        'cmd' => "$exe Text_processing_Max_licenses_in_use.p6 < mlijobs.txt"
    },
    'Update_a_configuration_file' => {'file' => 'test.cfg',
        'cmd' => ["$exe Update_a_configuration_file.p6 --/needspeeling --seedsremoved --numberofbananas=1024 --numberofstrawberries=62000 test.cfg\n",
                  "cat test.cfg\n"]
    },
    'Word_count' => {'file' => 'lemiz.txt', 'cmd' => "$exe Word_count.p6 lemiz.txt 10"},
    'Zhang_Suen_thinning_algorithm' => {'file' => 'rc-image.txt','cmd' => "$exe Zhang_Suen_thinning_algorithm.p6 rc-image.txt"},
    'I_before_E_except_after_C0' => {'file' => 'unixdict.txt'},
    'Stream_Merge' => {'skip' => 'needs input files'},
    'Ordered_words' => {'file' => 'unixdict.txt','cmd' => "$exe Ordered_words.p6 < unixdict.txt"},
    'User_defined_pipe_and_redirection_operators' => {'file' => 'List_of_computer_scientists.lst'},
    'Letter_frequency' => {'file' => 'List_of_computer_scientists.lst',
         'cmd' => "cat List_of_computer_scientists.lst | $exe Letter_frequency.p6"
     },
    'Hello_world_Line_printer0' => {'skip' => 'needs line printer attached'},
    'Hello_world_Line_printer1' => {'skip' => 'needs line printer attached'},
    'Narcissist' => {'skip' => 'needs to run from command line'},
    'Anagrams' => {'file' => 'unixdict.txt'},
    'Anagrams_Deranged_anagrams' => {'file' => 'unixdict.txt'},
    'Semordnilap' => {'file' => 'unixdict.txt'},
    'Textonyms' => {'file' => 'unixdict.txt'},
    'Handle_a_signal' => {'skip' => 'needs user intervention'},
    'Copy_a_string2' => {'skip' => 'nyi'},
    'Flow_control_structures' => {'skip' => 'nyi'},
    'Arena_storage_pool' => {'skip' => 'ok to skip; no code'},
    'Aspect_Oriented_Programming' => {'skip' => 'ok to skip; no code'},
    'Check_output_device_is_a_terminal' => {'skip' => 'ok to skip; no code'},
    'Command_line_arguments' => {'skip' => 'ok to skip; no code'},
    'Hello_world_Newbie' => {'skip' => 'ok to skip; no code'},
    'Naming_conventions' => {'skip' => 'ok to skip; no code'},
    'Operator_precedence' => {'skip' => 'ok to skip; no code'},
    'Random_number_generator__included_' => {'skip' => 'ok to skip; no code'},
    'Shell_one_liner' => {'skip' => 'ok to skip; no code'},
    'Special_characters' => {'skip' => 'ok to skip; no code'},
    'Table_creation' => {'skip' => 'ok to skip; no code'},
    'Variable_size_Set' => {'skip' => 'ok to skip; no code'},
    'Atomic_updates' => {'cmd' => "ulimit -t 10\n$exe Atomic_updates.p6\n"},
    'Birthday_problem1' => {'cmd' => "ulimit -t 5\n$exe Birthday_problem1.p6\n"},
    'Count_in_factors0' => {'cmd' => "ulimit -t 1\n$exe Count_in_factors0.p6\n"},
    'Count_in_octal' => {'cmd' => "ulimit -t 1\n$exe Count_in_octal.p6\n"},
    'Draw_a_clock' => {'cmd' => "ulimit -t 1\n$exe Draw_a_clock.p6\n"},
    'Echo_server' => {'skip' => 'runs forever'},
    'Chat_server' => {'skip' => 'runs forever'},
    'Elementary_cellular_automaton_Infinite_length' => {'cmd' => "ulimit -t 2\n$exe Elementary_cellular_automaton_Infinite_length.p6\n"},
    'Find_limit_of_recursion' => {'cmd' => "ulimit -t 6\n$exe Find_limit_of_recursion.p6\n"},
    'Forest_fire' => {'cmd' => ["ulimit -t 20\n$exe Forest_fire.p6\n","$exe -e'print \"\e[0m\ \e[H\e[2J\"'"]},
    'Fractran1' => {'cmd' => "ulimit -t 10\n$exe Fractran1.p6\n"},
    'Integer_sequence' => {'cmd' => "ulimit -t 1\n$exe Integer_sequence.p6\n"},
    'Linux_CPU_utilization' => {'skip' => 'takes forever to time out', 'cmd' => "ulimit -t 1\n$exe Linux_CPU_utilization.p6\n"},
    'Loops_Infinite0' => {'cmd' => "ulimit -t 1\n$exe Loops_Infinite0.p6\n"},
    'Loops_Infinite1' => {'cmd' => "ulimit -t 1\n$exe Loops_Infinite1.p6\n"},
    'Pi' => {'cmd' => "ulimit -t 5\n$exe Pi.p6\n"},
    'Pythagorean_triples1' => {'cmd' => "ulimit -t 1\n$exe Pythagorean_triples1.p6\n"},
    'Pythagorean_triples2' => {'cmd' => "ulimit -t 8\n$exe Pythagorean_triples2.p6\n"},
    'Pythagorean_triples3' => {'cmd' => "ulimit -t 8\n$exe Pythagorean_triples3.p6\n"},
    'Wireworld' => {'cmd' => "$exe Wireworld.p6 --stop-on-repeat"},
    'Memory_layout_of_a_data_structure0' => {'skip' => 'speculation'},
    'Memory_layout_of_a_data_structure1' => {'skip' => 'speculation'},
    'Loop_over_multiple_arrays_simultaneously3' => {'skip' => 'stub'},
    'Loop_over_multiple_arrays_simultaneously4' => {'skip' => 'stub'},
    'Conditional_structures1' => {'skip' => 'user input'},
    'Create_a_two_dimensional_array_at_runtime0' => {'cmd' => "echo \"5x35\n\" | $exe Create_a_two_dimensional_array_at_runtime0.p6"},
    'Create_a_two_dimensional_array_at_runtime1' => {'cmd' => "echo \"3x10\n\" | $exe Create_a_two_dimensional_array_at_runtime1.p6"},
    'Arithmetic_Integer' => {'cmd' => "echo \"27\n31\n\" | $exe Arithmetic_Integer.p6"},
    'Balanced_brackets0' => {'cmd' => "echo \"22\n\" | $exe Balanced_brackets0.p6"},
    'Balanced_brackets1' => {'cmd' => "echo \"22\n\" | $exe Balanced_brackets1.p6"},
    'Balanced_brackets2' => {'cmd' => "echo \"22\n\" | $exe Balanced_brackets2.p6"},
    'Balanced_brackets3' => {'cmd' => "echo \"22\n\" | $exe Balanced_brackets3.p6"},
    'Decision_tables' => {'skip' => 'user interaction'},
    'Dynamic_variable_names' => {'cmd' => "echo \"this-var\" | $exe Dynamic_variable_names.p6"},
    'Execute_HQ9_1' => {'skip' => 'user interaction'},
    'File_size_distribution' => {'cmd' => "$exe File_size_distribution.p6 '~'"},
    'Hello_world_Graphical' => {'skip' => 'user interaction, gui'},
    'Hello_world_Web_server' => {'skip' => 'user interaction, gui'},
    'Horizontal_sundial_calculations' => {'cmd' => "echo \"-4.95\n-150.5\n-150\n\" | $exe Horizontal_sundial_calculations.p6"},
    'Input_Output_for_Lines_of_Text0' => {
        'cmd' => "echo \"3\nhello\nhello world\nPack my Box with 5 dozen liquor jugs\" | $exe Input_Output_for_Lines_of_Text0.p6"
    },
    'Input_Output_for_Lines_of_Text1' => {
        'cmd' => "echo \"3\nhello\nhello world\nPack my Box with 5 dozen liquor jugs\" | $exe Input_Output_for_Lines_of_Text1.p6"
    },
    'Input_Output_for_Pairs_of_Numbers' => {
        'cmd' => "echo \"5\n1 2\n10 20\n-3 5\n100 2\n5 5\" | $exe Input_Output_for_Pairs_of_Numbers.p6"
    },
    'Reverse_words_in_a_string' => { 'file' => 'reverse.txt','cmd' => "$exe Reverse_words_in_a_string.p6 reverse.txt"},
    'Rosetta_Code_Find_bare_lang_tags' => {'file' => 'rcpage','cmd' => "$exe Rosetta_Code_Find_bare_lang_tags.p6 rcpage"},
    'Rosetta_Code_Fix_code_tags' => {'file' => 'rcpage','cmd' => "$exe Rosetta_Code_Fix_code_tags.p6 rcpage"},
    'Integer_comparison0' => {'cmd' => "echo \"9\n17\" | $exe Integer_comparison0.p6"},
    'Integer_comparison2' => {'cmd' => "echo \"9\n17\" | $exe Integer_comparison2.p6"},
    'Inverted_index' => {'file' => 'unixdict.txt','cmd' => "echo \"rosetta\ncode\nblargg\n\" | $exe Inverted_index.p6 unixdict.txt\n"},
    'Keyboard_input_Obtain_a_Y_or_N_response' => {'skip' => 'user interaction, custom shell'},
    'Keyboard_macros' => {'skip' => 'user interaction, custom shell'},
    'Longest_string_challenge' => {'cmd' => "echo \"a\nbb\nccc\nddd\nee\nf\nggg\n\" | $exe Longest_string_challenge.p6\n"},
    'Magic_squares_of_doubly_even_order' => {'cmd' => "$exe Magic_squares_of_doubly_even_order.p6 12"},
    'Magic_squares_of_singly_even_order' => {'cmd' => "$exe Magic_squares_of_singly_even_order.p6 10"},
    'Magic_squares_of_odd_order' => {'cmd' => "$exe Magic_squares_of_odd_order.p6 11"},
    'Menu' => {'cmd' => "echo \"2\n\" | $exe Menu.p6\n"},
    'Morse_code' => {'cmd' => "echo \"Howdy, World!\n\" | $exe Morse_code.p6\n"},
    'Number_names0' => {'skip' => 'user interaction'},
    'One_time_pad0' => {'skip' => 'user interaction, manual intervention'},
    'One_time_pad1' => {'skip' => 'user interaction, manual intervention'},
    'Price_fraction0' => {'cmd' => "echo \".86\" | $exe Price_fraction0.p6\n"},
    'Price_fraction1' => {'cmd' => "echo \".74\" | $exe Price_fraction1.p6\n"},
    'Price_fraction2' => {'cmd' => "echo \".35\" | $exe Price_fraction2.p6\n"},
    'Simple_windowed_application' => {'skip' => 'user interaction, gui'},
    'Sleep' => {'cmd' => "echo \"3.86\" | $exe Sleep.p6\n"},
    'Sparkline_in_unicode' => {
        'cmd' => ["echo \"9 18 27 36 45 54 63 72 63 54 45 36 27 18 9\" | $exe Sparkline_in_unicode.p6\n",
                  "echo \"1.5, 0.5 3.5, 2.5 5.5, 4.5 7.5, 6.5\" | $exe Sparkline_in_unicode.p6\n",
                  "echo \"3 2 1 0 -1 -2 -3 -4 -3 -2 -1 0 1 2 3\" | $exe Sparkline_in_unicode.p6\n"]
    },
    'Temperature_conversion0' => {'cmd' => "echo \"21\" | $exe Temperature_conversion0.p6\n"},
    'Temperature_conversion1' => {
        'cmd' => ["echo \"0\" | $exe Temperature_conversion1.p6\n",
                  "echo \"0c\" | $exe Temperature_conversion1.p6\n",
                  "echo \"212f\" | $exe Temperature_conversion1.p6\n",
                  "echo \"-40c\" | $exe Temperature_conversion1.p6\n"]
    },
    'Trabb_Pardo_Knuth_algorithm' => {'cmd' => "echo \"10 -1 1 2 3 4 4.3 4.305 4.303 4.302 4.301\" | $exe Trabb_Pardo_Knuth_algorithm.p6\n"},
    'Truth_table' => {
        'cmd' => ["$exe Truth_table.p6 'A ^ B'\n",
                  "$exe Truth_table.p6 'foo & bar | baz'\n",
                  "$exe Truth_table.p6 'Jim & (Spock ^ Bones) | Scotty'\n"]
    },
    'User_input_Graphical' => {'skip' => 'user interaction, gui'},
    'User_input_Text' => { 'cmd' => "echo \"Rosettacode\n10\" $exe User_input_Text.p6 "},
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
    'Rock_paper_scissors0' => {'skip' => 'user interaction, game'},
    'Snake' => {'skip' => 'user interaction, game'},
    'Snake_And_Ladder' => {'skip' => 'user interaction, game'},
    'Tic_tac_toe' => {'skip' => 'user interaction, game'},

# image producing tasks
    'Dragon_curve' => { 'cmd' => ["$exe Dragon_curve.p6 > Dragon-curve-perl6.svg\n","$view Dragon-curve-perl6.svg"]},
    'Bitmap_B_zier_curves_Cubic' => { 'cmd' => ["$exe Bitmap_B_zier_curves_Cubic.p6 > Bezier-cubic-perl6.ppm\n","$view Bezier-cubic-perl6.ppm"]},
    'Bitmap_B_zier_curves_Quadratic' => { 'cmd' => ["$exe Bitmap_B_zier_curves_Quadratic.p6 > Bezier-quadratic-perl6.ppm\n","$view Bezier-quadratic-perl6.ppm"]},
    'Bitmap_Write_a_PPM_file' => { 'cmd' => ["$exe Bitmap_Write_a_PPM_file.p6 > Bitmap-write-ppm-perl6.ppm\n","$view Bitmap-write-ppm-perl6.ppm"]},
    'Fractal_tree'  => { 'cmd' => ["$exe Fractal_tree.p6 > Fractal-tree-perl6.svg\n","$view Fractal-tree-perl6.svg"]},
    'Plot_coordinate_pairs' => { 'cmd' => ["$exe Plot_coordinate_pairs.p6 > Plot-coordinate-pairs-perl6.svg\n","$view Plot-coordinate-pairs-perl6.svg"]},
    'Pythagoras_tree' => { 'cmd' => ["$exe Pythagoras_tree.p6 > Pythagoras-tree-perl6.svg\n","$view Pythagoras-tree-perl6.svg"]},
    'Pentagram' => { 'cmd' => ["$exe Pentagram.p6 > Pentagram-perl6.svg\n","$view Pentagram-perl6.svg"]},
    'Sierpinski_triangle_Graphical' => { 'cmd' => ["$exe Sierpinski_triangle_Graphical.p6 > Sierpinski_triangle_Graphical-perl6.svg\n","$view Sierpinski_triangle_Graphical-perl6.svg"]},
    'Yin_and_yang0' => { 'cmd' => ["$exe Yin_and_yang0.p6 > Yin_and_yang-perl6.svg\n","$view Yin_and_yang-perl6.svg"]},
    'Sierpinski_pentagon' => { 'cmd' => ["$exe Sierpinski_pentagon.p6 > Sierpinski_pentagon-perl6.svg\n","$view Sierpinski_pentagon-perl6.svg"]},
    'Superellipse' => { 'cmd' => ["$exe Superellipse.p6 > Superellipse-perl6.svg\n","$view Superellipse-perl6.svg"]},
    'Mandelbrot_set' => { 'cmd' => ["$exe Mandelbrot_set.p6 255 > Mandelbrot-set-perl6.ppm\n","$view Mandelbrot-set-perl6.ppm"]},
    'Bitmap_Histogram' => {'file' => 'Lenna.ppm', 'cmd' => ["$exe Bitmap_Histogram.p6\n","$view Lenna-bw.pbm"]},
    'Bitmap_Read_a_PPM_file' => {'file' => 'camelia.ppm', 'cmd' => ["$exe Bitmap_Read_a_PPM_file.p6\n","$view camelia-gs.pgm"]},
    'Bitmap_Read_an_image_through_a_pipe' => {'file' => 'camelia.png', 'cmd' => ["$exe Bitmap_Read_an_image_through_a_pipe.p6\n","$view camelia.ppm"]},
    'Grayscale_image' => {'file' => 'default.ppm', 'cmd' => ["$exe Grayscale_image.p6\n","$view default.pgm"]},
    'Draw_a_sphere' => { 'cmd' => ["$exe Draw_a_sphere.p6\n","$view sphere-perl6.pgm"]},
    'Death_Star' => { 'cmd' => ["$exe Death_Star.p6\n","$view deathstar-perl6.pgm"]},
    'Archimedean_spiral' => {'cmd' => ["$exe Archimedean_spiral.p6\n","$view Archimedean-spiral-perl6.png"]},
    'Julia_set' => {'cmd' => ["$exe Julia_set.p6\n","$view Julia-set-perl6.png"]},
    'Chaos_game' => {'cmd' => ["$exe Chaos_game.p6\n","$view Chaos-game-perl6.png"]},
    'Color_wheel' => {'cmd' => ["$exe Color_wheel.p6\n","$view Color-wheel-perl6.png"]},
    'Barnsley_fern' => {'cmd' => ["$exe Barnsley_fern.p6\n","$view Barnsley-fern-perl6.png"]},
    'Voronoi_diagram' => {
        'cmd' => ["$exe Voronoi_diagram.p6\n",
                  "$view Voronoi-Minkowski-perl6.png",
                  "$view Voronoi-Taxicab-perl6.png",
                  "$view Voronoi-Euclidean-perl6.png",
                 ]
    },
    'Kronecker_product_based_fractals' => {
        'cmd' => ["$exe Kronecker_product_based_fractals.p6\n",
                  "$view kronecker-vicsek-perl6.png",
                  "$view kronecker-carpet-perl6.png",
                  "$view kronecker-six-perl6.png",
                 ]
    },
    'Munching_squares0' => {'cmd' => ["$exe Munching_squares0.p6\n","$view munching0.ppm"]},
    'Munching_squares1' => {'cmd' => ["$exe Munching_squares1.p6\n","$view munching1.ppm"]},
    'Pinstripe_Display' => {'cmd' => ["$exe Pinstripe_Display.p6\n","$view pinstripes.pgm"]},
    'Plasma_effect' => {'cmd' => ["$exe Plasma_effect.p6\n","$view Plasma-perl6.png"]},
    )
}

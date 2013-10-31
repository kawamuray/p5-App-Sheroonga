requires 'perl', '5.010001';
requires 'Caroline';
requires 'Getopt::Long';
requires 'Net::Groonga::HTTP';
requires 'JSON';
requires 'Text::ParseWords';

on 'test' => sub {
    requires 'Test::More', '0.98';
};


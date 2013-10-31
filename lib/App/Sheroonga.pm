package App::Sheroonga;
use 5.010001;
use strict;
use warnings;
use Caroline;
use Getopt::Long qw( GetOptionsFromArray );
use List::MoreUtils qw( first_index );
use Net::Groonga::HTTP;
use JSON;
use Text::ParseWords ();

use constant DEBUG => $ENV{SHEROONGA_DEBUG};

our $VERSION = "0.01";

use App::Sheroonga::Command;
our %GroongaCommands = %App::Sheroonga::Command::GroongaCommands;
our %GroongaOptions = %App::Sheroonga::Command::GroongaOptions;

sub CLI {
    my ($class, @args) = @_;
    GetOptionsFromArray(\@args, \my %opts,
        qw( version help )
    );

    binmode $_, ':utf8' for (\*STDIN, \*STDOUT);

    if ($opts{help}) {
        CORE::print $class->usage;
    } elsif ($opts{version}) {
        CORE::print __PACKAGE__, ' ', $VERSION;
    } else {
        my $end_point = shift @args
            or die "end_point not specified";
        my $sheroonga = $class->new(
            end_point => $end_point,
            stdin     => \*STDIN,
            stdout    => \*STDOUT,
        );

        if (@args) { # Required to run a single command
            $sheroonga->exec(@args);
        } else {
            $sheroonga->start_repl;
        }
    }
    0; # Exit success
}

sub usage {
    <<EOS
Usage: $0 [options] <endpoint_uri>
Options:
  --help          Show this help
  --version       Show sheroonga version
EOS
}

sub new {
    my ($class, %args) = @_;

    my $self = bless \%args, $class;

    $self->{caroline} = Caroline->new(
        completion_callback => sub {
            $self->completion(@_);
        },
    );
    $self->{groonga} = Net::Groonga::HTTP->new(
        end_point => $args{end_point},
        ua => $args{groonga_http_ua} || Furl->new(
            agent => __PACKAGE__."/$VERSION",
            timeout => $args{timeout} // 10,
        ),
    );
    $self->{json} = JSON->new->utf8->pretty; #->canonical;
    if (DEBUG) {
        open $self->{debug_fh}, '>', DEBUG
            or die "Can't open ".DEBUG." for debug output: $!";
    }

    $self;
}

sub debug {
    my ($self, @msgs) = @_;

    my $fh = $self->{debug_fh} or return;
    print $fh @msgs;
}

sub start_repl {
    my ($self) = @_;

    # STD(IN|OUT) is hardcoded in Caroline
    local *STDIN = $self->{stdin};
    local *STDOUT = $self->{stdout};

    while (defined(my $l = $self->{caroline}->readline('groonga> '))) {
        my ($command, @args) = $self->parse_input($l);
        if (defined $command) {
            my $res = $self->exec($command, @args);
            warn "resposne_code = " .$res->http_response->code;
            warn "data = ".$res->data;
            # We can't use $res->is_success here because
            # Groonga http server returns non-success(2xx)
            # codes even if HTTP request had succeed.
            # I believe(or I hope) Groonga httpd does not return
            # 5xx codes except in case they have "real" error.
            if ($res->http_response->code =~ /^5/) {
                # HTTP request has failed (not a groonga error)
                $self->print(sprintf "HTTP request to %s failed. [%s] %s",
                             $self->{groonga}->end_point,
                             $res->http_response->code,
                             $res->http_response->body);
            } else {
                my $json = $res->http_response->content;
                my $data = eval {
                    $self->{json}->decode($json)
                };
                if ($@) {
                    $self->print("Can't decode HTTP response as JSON: $json");
                } else {
                    $self->print_response($command, $data);
                }
            }
            last if $command eq 'quit';
        }
    }
}

sub exec {
    my ($self, $command, @args) = @_;

    return unless $GroongaCommands{$command};
    my %args = $self->make_hash_args($command, @args);
    $self->{groonga}->call($command, %args);
}

sub make_hash_args {
    my ($self, $command, @args) = @_;

    my @aseq = @{ $GroongaCommands{$command}{args} || [] };
    GetOptionsFromArray(\@args, \my %args, map { "$_=s" } @aseq);

    while (my $arg = shift @args) {
        shift @aseq while @aseq && defined $args{$aseq[0]};
        if (@aseq) {
            $args{shift @aseq} = $arg;
        } else {
            $self->warn("Unknown argument: $arg");
        }
    }
    %args;
}

sub print_response {
    my ($self, $command, $data) = @_;

    if ($data->[0][0] == 0) {
        $self->print($self->{json}->encode($data));
    } else {
        $self->print_grn_error($data);
    }
}

sub print_grn_error {
    my ($self, $data) = @_;

    $self->print(sprintf <<EOS, $data->[0][0], $data->[0][3]);
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Groonga Error @
Code    : %s
Message : %s
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOS
}

sub print {
    my ($self, @args) = @_;
    my $fh = $self->{stdout};
    CORE::print $fh @args;
}

sub parse_input {
    my ($self, $line) = @_;
    Text::ParseWords::shellwords($line);
}

sub completion {
    my ($self, $line) = @_;

    use Data::Dumper;
    $self->debug("completion: ".Dumper($line)) if DEBUG;

    my $have_prefix = $line =~ /\S\z/o;
    my ($command, @args) = $self->parse_input($line);
    return if !defined $command && $line =~ /\S/; # Invalid input, can't complete
    map {
        my $ahead = $line;
        if ($have_prefix) {
            my $re = join '', map { "\Q$_\E?" } split //, $_;
            $ahead =~ s/$re\z//;
        }
        $ahead.$_;
    } $self->completion_dispatch($have_prefix, $self->parse_input($line));
}

sub completion_dispatch {
    my ($self, $have_prefix, $command, @rest) = @_;

    # INPUT                        => CANDIDATES
    # (no input)                   => commands
    # se(EOL)                      => "select"
    # select (EOL)                 => tables/options for select
    # select --(EOL)               => options for select
    # select ta(EOL)               => tables
    # select --table (EOL)         => tables
    # select --query (EOL)         => nothing
    # table_create --key_type(EOL) => data types

    if (!defined $command || !@rest && $have_prefix) {
        return $self->complete_command($command);
    }
    unless (@rest) {
        return $self->complete_command_any($command);
    }

    my $last = pop @rest;
    my $last_is_opt = $last =~ /\A-/;
    if ($have_prefix) {
        if ($last_is_opt) {
            return $self->complete_command_opts($command, $last);
        } else {
            my $opt = pop @rest;
            return ($opt && $opt =~ /\A-/)
                ? $self->complete_option_args($opt, $last, \@rest)
                : $self->complete_command_any($command, $last);
        }
    } else {
        if ($last_is_opt) {
            return $self->complete_option_args($last);
        } else {
            return $self->complete_command_any($command);
        }
    }
}

sub complete_command {
    my ($self, $prefix) = @_;

    my @commands = keys %GroongaCommands;
    if (defined $prefix) {
        @commands = grep /^\Q$prefix\E/, @commands;
    }
    @commands;
}

sub complete_command_args {
    my ($self, $command, $prefix, $aheads) = @_;

    my $cdata = $GroongaCommands{$command} or return;
    my @available_fields = @{ $cdata->{args} || [] };
    my $ignore_next;
    for my $arg (@{ $aheads || [] }) {
        if ($ignore_next) {
            $ignore_next = 0;
            next;
        }
        if ($arg =~ s/\A--?//) {
            # If some option has been specified, assume that field
            # has already passed and exclude from candidates
            my $ix = first_index { $_ eq $arg } @available_fields;
            splice @available_fields, $ix, 1 if defined $ix;
            # Now the element in position $ix is an argument for previous option
            # or next option or nothing
            # XXX WTF?
            $ignore_next = (defined $available_fields[$ix] && $available_fields[$ix] !~ /^-/);
        } else {
            shift @available_fields;
        }
    }
    @available_fields
        ? $self->complete_option_args(shift @available_fields, $prefix, $command)
        : ();
}

sub complete_command_opts {
    my ($self, $command, $prefix) = @_;

    ($prefix //= '') =~ s/\A--?//;
    my $cdata = $GroongaCommands{$command} or return;
    my @candidates = @{ $cdata->{args} || [] };
    if ($prefix) {
        @candidates = grep /^\Q$prefix\E/, @candidates;
    }
    @candidates;
}

sub complete_command_any {
    my ($self, $command, $prefix, $rest) = @_;

    ($self->complete_command_args($command, $prefix, $rest),
     $self->complete_command_opts($command, $prefix));
}

sub complete_option_args {
    my ($self, $option, $prefix, $command) = @_;

    $option =~ s/\A--?//;

    my $opdata = $GroongaOptions{$option};
    if (defined $command && $GroongaCommands{$command} &&
        $GroongaCommands{$command}{opts} && $GroongaCommands{$command}{opts}{$option}) {
        $opdata = $GroongaCommands{$command}{opts}{$option};
    }
    return unless $opdata;

    my @candidates = ref($opdata) eq 'ARRAY' ? @$opdata : $self->$opdata($prefix);
    if (defined $prefix) {
        @candidates = grep /^\Q$prefix\E/, @candidates;
    }
    @candidates;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::Sheroonga - It's new $module

=head1 SYNOPSIS

    # In script
    #!perl
    use App::Sheroonga;
    exit App::Sheroonga->CLI(@ARGV);

    # In library
    use strict;
    use warnings;
    use App::Sheroonga;

    my $sheroonga = App::Sheroonga->new(end_point => "GROONGA URL");
    my $res = $sheroonga->exec('select', table => 'TableA', query => 'col1:@foo');

    # You can use parse_input() method to parse combined command string
    my $res = $sheroonga->exec($sheroonga->parse_input(
     'table_create TableFoo --default_tokenizer TokenBigram'
    ));

=head1 DESCRIPTION

App::Sheroonga is ...

=head1 LICENSE

Copyright (C) Yuto KAWAMURA(kawamuray).

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Yuto KAWAMURA(kawamuray) E<lt>kawamuray.dadada@gmail.comE<gt>

=cut


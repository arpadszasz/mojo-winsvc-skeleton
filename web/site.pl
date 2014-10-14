#!/usr/bin/env perl

package main;

use 5.10.1;
use strict;
use warnings;
use FindBin '$Bin';
use lib "$Bin/lib";
use File::Slurp;
use Config::Tiny;
use File::Basename;
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use DBI;
use Win32::EventLog;
use Site;

my $RealBin;
my $config;
my $dbh;
my $odbc_dsn        = $config->{odbc}->{alias};
my $odbc_user       = $config->{odbc}->{username};
my $odbc_pass       = $config->{odbc}->{password};
my $host            = $config->{server}->{address} || 'localhost';
my $port            = $config->{server}->{port} || 3000;
my $ini_file        = $config->{product}->{configuration} || 'program.ini';
my $log_file        = $config->{log}->{file} || 'error.log';
my $write_event_log = $config->{log}->{event} || 0;

BEGIN {
    $ENV{MOJO_MODE}      ||= 'production';
    $ENV{MOJO_LOG_LEVEL} ||= 'error';
    $ENV{DBI_TRACE}      ||= undef;

    if ($PerlSvc::VERSION) {
        $RealBin = ( fileparse( PerlSvc::exe() ) )[1];
        $ENV{MOJO_HOME} = $RealBin;

        $config
          = Config::Tiny->new->read_string( scalar read_file( \*DATA ) );

        $PerlSvc::Name
          = ( lc( $config->{product}->{name} =~ s/\s/-/gr ) ) . '-site';
        $PerlSvc::DisplayName = $config->{product}->{name} . ' Site';

        if ( defined $ARGV[0] ) {
            if ( $ARGV[0] eq '-dd' ) {
                $ENV{MOJO_LOG_LEVEL} = 'debug';
                $ENV{DBI_TRACE}      = 2;
            }
            elsif ( $ARGV[0] eq '-d' ) {
                $ENV{MOJO_LOG_LEVEL} = 'debug';
            }
        }
    }
    else {
        my $ini_file = "$Bin/../release.ini";
        die qq/Can't find configuration file [$ini_file]!/ unless $ini_file;
        $config  = Config::Tiny->new->read($ini_file);
        $RealBin = $FindBin::Bin;
    }
}


sub start_daemon {
    eval {
        $dbh = DBI->connect(
            "dbi:ODBC:$odbc_dsn", $odbc_user, $odbc_pass,
            { PrintError => 0, RaiseError => 1 }
        );
        DBI->trace( $ENV{DBI_TRACE} ) if $ENV{DBI_TRACE};
    };

    my $app = Site->new(
        dbh       => $dbh,
        ini_file  => "$RealBin/$ini_file",
        log_file  => "$RealBin/$log_file",
        log_event => \&log_event,
    );

    state $daemon;
    state $loop_ini_id;
    state $loop_db_id;
    if ($daemon) {
        $daemon->stop;
        Mojo::IOLoop->remove($loop_ini_id);
        Mojo::IOLoop->remove($loop_db_id);
    }
    $daemon = Mojo::Server::Daemon->new(
        app    => $app,
        listen => [ 'http://' . $host . ':' . $port ]
    );
    $daemon->start;

    # detect INI config file changes every 5s
    $loop_ini_id = Mojo::IOLoop->recurring(
        5 => sub {
            my $ini = "$RealBin/$ini_file";
            return unless -r $ini;
            my $current_mtime = ( stat($ini) )[9];
            state $cached_mtime ||= $current_mtime;
            if ( $current_mtime > $cached_mtime ) {
                my $message = "Configuration changed, restarting daemon";
                log_message( $message, 'info' );
                log_event( [ 'Configuration change', $message ], 'info' );
                $cached_mtime = $current_mtime;
                start_daemon();
            }
        }
    );

    # detect DB connection every 30s
    $loop_db_id = Mojo::IOLoop->recurring(
        30 => sub {
            if ( not $dbh or ( $dbh and not $dbh->ping ) ) {
                my $message = "No DB server connection, restarting daemon";
                log_message( "Database error: $message", 'error' );
                log_event( [ 'Database error', $message ], 'error' );
                start_daemon();
            }
        }
    );

    while (1) {
        if (    $PerlSvc::VERSION
            and PerlSvc::RunningAsService()
            and not PerlSvc::ContinueRun() ) {
            last;
        }
        Mojo::IOLoop->one_tick;
    }

    return;
}

sub log_message {
    my $message = shift;
    my $level = shift || 'error';

    return unless $message;

    open( my $log_fh, '>>', "$RealBin/$log_file" );
    say $log_fh ( '[' . scalar localtime . '] [' . $level . '] ' . $message );
    close $log_fh;

    return;
}

sub log_event {
    my $message = shift;
    my $level = shift || 'error';

    my %event_type = (
        error => EVENTLOG_ERROR_TYPE,
        info  => EVENTLOG_INFORMATION_TYPE,
    );

    return unless $message;

    return
      if not( $PerlSvc::VERSION
        and PerlSvc::RunningAsService()
        and $write_event_log );

    my $event_log = Win32::EventLog->new($PerlSvc::Name);
    $event_log->Report(
        {
            Source    => $PerlSvc::DisplayName,
            EventType => $event_type{$level} || $event_type{error},
            Strings   => join "\0", @{$message},
        }
    );
    $event_log->Close;

    return;
}

package PerlSvc;

our $Name;
our $DisplayName;

sub Startup {
    main::start_daemon();
}

sub Interactive {
    main::start_daemon();
}

sub Install {
    say "The $Name Service has been installed";
}

sub Remove {
    say "The $Name Service has been removed";
}

sub Help {
    say "$0 -d              show debugging output (Mojo)";
    say "$0 -dd             show more debugging output (Mojo + DBI)";
}

package main;

start_daemon() if not $PerlSvc::VERSION;

exit;

__DATA__

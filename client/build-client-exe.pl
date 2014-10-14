#!perl

use 5.10.1;
use strict;
use warnings;
use utf8;
use FindBin q($Bin);
use File::Slurp;
use File::Glob q(bsd_glob);
use Config::Tiny;
use Time::Piece;
use Sys::Hostname;
use Config;
use Cwd;
use File::Find;
use Template;
use Term::ANSIColor;
use Win32::Console::ANSI;

$|++;

my $ini_file = "$Bin/../release.ini";
if ( not -r $ini_file ) {
    log_message( qq/Can't find configuration file [$ini_file]!/, 'error' );
    die;
}

my $config = Config::Tiny->new->read($ini_file);

my %product = (
    name    => $config->{product}->{name},
    version => $config->{product}->{version}
      || localtime->strftime("%Y.%m.%d.%H%M"),
    company => $config->{product}->{company},
);
my $perlapp = find_compiler('perlapp');
my %app = ( script => qq(client/browser.pl) );
my $output = ( lc( $product{name} =~ s/\s/-/gr ) ) . '-client';

chdir($Bin);

install_dependencies();
check_syntax();
create_exe();

log_message('Client release creation succeeded!', 'info');

exit 0;

sub install_dependencies {
    if ( qx(ppm repo list) !~ /wx/ ) {
        # install wxPerl packages from Mark Dootson's repo
        system( 'ppm', 'remove', '--force', 'Alien::wxWidgets', 'Wx' );
        system( 'ppm', 'repo', 'add', 'http://www.wxperl.co.uk/repo29/',
            'wx29' );
        system( 'ppm', 'repo', '1', 'off' );
        system( 'ppm', 'install', 'Alien::wxWidgets', 'Wx' );
        system( 'ppm', 'repo', '1', 'on' );
    }

    system(
        'ppm', 'install', 'Alien::wxWidgets', 'Wx', 'Wx::Perl::Packager',
        'IO::Socket::PortState', 'MinGW'
      ) == 0
      or do {
        log_message(
            'Problem installing client Perl module dependencies!',
            'error'
        );
        die;
      };

    return;
}

sub check_syntax {
    system( 'perl', "-wc", "$Bin/../$app{script}" ) == 0
      or do {
        log_message(
            'Application source code contains syntax errors!',
            'error'
        );
        die;
      };

    log_message( 'Syntax checking succeeded!', 'info' );

    return;
}

sub create_exe {
    require Alien::wxWidgets;
    Alien::wxWidgets->import;

    my $pdk_folder = qq($Bin/../pdk);
    mkdir $pdk_folder unless -d $pdk_folder;

    my $perlapp_project = qq($pdk_folder/$output.perlapp);

    my $temp_script = $app{script};
    $temp_script =~ s/browser/_browser/;
    write_file( "$Bin/../$temp_script",
        ( read_file( "$Bin/../$app{script}" ) . "\n" . read_file($ini_file) )
    );

    my %perl_lib_path = (
        site_lib        => $Config{installsitelib},
        alien_wxwidgets => Alien::wxWidgets->shared_library_path,
    );

    my @dlls;
    find(
        sub {
            if (/\.dll$/) {
                push( @dlls, $_ );
            }
        },
        $perl_lib_path{alien_wxwidgets},
    );

    my $template = <<'EOF';
[%- USE date; current_date = date.format( date.now, '%Y-%m-%d %H:%M:%S' ) -%]
#![% perlapp.replace("perlapp", "perlapp-gui") %]
PAP-Version: 1.0
Packer: [% perlapp %]
Script: ../[% temp_script %]
Cwd: [% cwd %]
Add: Wx::
[%- FOREACH dll = dlls %]
Bind: [% dll %][file=[% perl_lib_path.alien_wxwidgets %]/[% dll %],extract,mode=444]
[%- END %]
Bind: wxmain.dll[file=[% perl_lib_path.site_lib %]/auto/Wx/Wx.dll,extract,mode=666]
Byref: 0
Clean: 0
Date: [% current_date %]
Debug: 
Dependent: 0
Dyndll: 0
Exe: ../dist/[% output %].exe
Force: 1
Gui: 1
Hostname: [% hostname %]
Manifest: 
No-Compress: 0
No-Gui: 0
No-Logo: 0
Runlib: 
Shared: none
Singleton: 0
Tmpdir: 
Verbose: 1
Version-Comments: 
Version-CompanyName: [% product.company %]
Version-FileDescription: 
Version-FileVersion: 
Version-InternalName: 
Version-LegalCopyright: (C) [% date.format( date.now, '%Y' ) %] [% product.company %] 
Version-LegalTrademarks: 
Version-OriginalFilename: 
Version-ProductName: [% product.name %] Client
Version-ProductVersion: [% product.version %]
Warnings: 1
Xclude: 0
EOF

    my $tt = Template->new;
    $tt->process(
        \$template, {
            ini_file      => $ini_file,
            cwd           => getcwd(),
            hostname      => hostname(),
            dlls          => \@dlls,
            output        => $output,
            perl_lib_path => \%perl_lib_path,
            perlapp       => $perlapp,
            product       => \%product,
            temp_script   => $temp_script,
        },
        $perlapp_project
    );
    if ( $tt->error ) {
        die $tt->error;
    }
    else {
        log_message( "Created PerlApp project file [$perlapp_project]",
            'debug' );
    }

    system( $perlapp, $perlapp_project ) == 0
      or do {
        log_message( 'Creating client exe failed!', 'error' );
        die;
      };

    unlink "$Bin/../$temp_script";

    log_message( "Creating client exe succeeded [$output.exe]", 'info' );

    return;
}

sub find_compiler {
    my $compiler = shift;

    my %exe = (
        innosetup => 'ISCC.exe',
        perlapp   => 'perlapp.exe',
        perlsvc   => 'perlsvc.exe',
    );

    if ( $config->{compiler}->{$compiler} ) {
        my $exe_path
          = $config->{compiler}->{$compiler} . '/' . $exe{$compiler};
        if ( -x $exe_path ) {
            log_message( "Found $compiler compiler at [$exe_path]", 'debug' );
            return $exe_path;    
        }
        
    }
    
    my $program_folder;
    given ($compiler) {
        when (/innosetup/) { $program_folder = 'Inno Setup' }
        when (/perl(?:app|svc)/) {
            $program_folder = 'ActiveState Perl Dev Kit*/bin'
        }
    }
    if ($program_folder) {
        foreach (
            bsd_glob( $ENV{PROGRAMFILES} . qq(*/*$program_folder*) ) ) {
            my $exe_path = $_ . '/' . $exe{$compiler};
            log_message(
                "Found $compiler compiler at [$exe_path]\n",
                'debug'
            );
            return $exe_path if -x $exe_path;
        }
    }

    die "Compiler $compiler not found in path! Please configure it in release.ini!";

    return;
}

sub log_message {
    my $message = shift;
    my $level = shift || 'warn';

    my %severity = (
        debug => { level => 'DEBUG', color => 'bold yellow' },
        error => { level => 'ERROR', color => 'bold red' },
        info  => { level => 'INFO',  color => 'bold green' },
    );
    my $timestamp = localtime->strftime('%Y-%m-%d %H:%M:%S');

    print color $severity{$level}->{color};
    say '['
      . $timestamp . '] '
      . $severity{$level}->{level} . ': '
      . $message;
    print color 'reset';

    return;
}

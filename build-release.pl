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
use Cwd;
use File::Find;
use Template;
use Term::ANSIColor;
use Win32::Console::ANSI;

END {
    say "Press any key to continue . . .";
    <>;
}

$|++;

my $ini_file = "$Bin/release.ini";
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
my $perlsvc = find_compiler('perlsvc');
my $innosetup = find_compiler('innosetup');
my %app       = (
    script    => qq(web/site.pl),
    modules   => qq(web/lib),
    templates => qq(web/templates),
);
my $output = ( lc( $product{name} =~ s/\s/-/gr ) ) . '-site';
my $installer
  = qq($product{company}-)
  . ( $product{name} =~ s/\s/-/gr )
  . q(-Site-installer-)
  . ( $product{version} =~ s/\.//gr );

chdir($Bin);

check_syntax();
create_server_exe();
create_client_exe();
create_installer();

log_message('Release creation succeeded!', 'info');

exit 0;

sub check_syntax {
    my @files;
    find(
        sub {
            if (/\.(?:pl|pm)$/) {
                my $file = $File::Find::name;
                push( @files, $file );
            }
        },
        'web',
    );

    foreach my $file (@files) {
        system( 'perl', "-I$app{modules}", "-wc", "$file" ) == 0
          or do {
            log_message( 'Application source code contains syntax errors!',
                'error' );
            die;
          };
    }

    log_message( 'Syntax checking succeeded!', 'info' );

    return;
}

sub create_server_exe {
    my $pdk_folder = qq($Bin/pdk);
    mkdir $pdk_folder unless -d $pdk_folder;

    my $perlsvc_project = qq($pdk_folder/$output.perlsvc);

    my $temp_script = $app{script};
    $temp_script =~ s/site/_site/;
    write_file( "$Bin/$temp_script",
        ( read_file( "$Bin/$app{script}" ) . "\n" . read_file($ini_file) )
    );

    my @modules;
    find(
        sub {
            if (/\.pm$/) {
                my $module = $File::Find::name;
                $module =~ s/^.*web\/lib\///;
                $module =~ s/\.pm$//;
                $module =~ s/\//::/g;
                push( @modules, $module );
            }
        },
        $app{modules},
    );

    my @templates;
    find(
        sub {
            if (/\.ep$/) {
                my $template = $File::Find::name;
                $template =~ s/^.*web\///;
                push( @templates, $template );
            }
        },
        $app{templates},
    );

    my $template = <<'EOF';
[%- USE date; current_date = date.format( date.now, '%Y-%m-%d %H:%M:%S' ) -%]
#![% perlsvc.replace("perlsvc", "perlsvc-gui") %]
PAP-Version: 1.0
Packer: [% perlsvc %]
Script: ../[% temp_script %]
Cwd: [% cwd %]
Add: Mojolicious::
Add: Mojo::
Add: DBD::ODBC::
Add: DBI::
Add: Net::LDAP::
[%- FOREACH module = modules %]
Add: [% module %]
[%- END -%]
[%- FOREACH template = templates %]
Bind: [% template %][file=../web/[% template %],text,extract,mode=666]
[%- END %]
Byref: 0
Clean: 0
Date: [% current_date %]
Debug: 
Dependent: 0
Dyndll: 0
Exe: ../dist/[% output %].exe
Force: 1
Gui: 0
Hostname: [% hostname %]
Lib: lib:../[% app.modules %]
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
Version-ProductName: [% product.name %]
Version-ProductVersion: [% product.version %]
Warnings: 1
Xclude: 0
EOF

    my $tt = Template->new;
    $tt->process(
        \$template, {
            app       => \%app,
            cwd       => getcwd(),
            hostname  => hostname(),
            modules   => \@modules,
            output    => $output,
            perlsvc   => $perlsvc,
            product   => \%product,
            templates => \@templates,
            temp_script   => $temp_script,
        },
        $perlsvc_project
    );
    if ( $tt->error ) {
        die $tt->error;
    }
    else {
        log_message( "Created PerlSvc project file [$perlsvc_project]",
            'debug' );
    }

    foreach my $action ( ( '--install auto', '--remove' ) ) {
        my $template = <<'EOF';
@echo off
echo Administrative permissions required. Detecting permissions...

net session >nul 2>&1
if %errorLevel% == 0 (
    [% output %].exe [% action %]
) else (
    echo Failure: Must be run as an administrator account!
)

pause >nul
EOF
        $tt->process(
            \$template, {
                action => $action,
                output => $output,
            },
            "$Bin/dist/"
              . ( $action =~ /install/ ? 'install' : 'remove' )
              . '-service.bat',
        );
        if ( $tt->error ) {
            die $tt->error;
        }
    }

    system( $perlsvc, $perlsvc_project ) == 0
      or do {
        log_message( 'Creating server exe failed!', 'error' );
        die;
      };

    unlink "$Bin/$temp_script";

    log_message( "Creating server exe succeeded [$output.exe]", 'info' );

    return;
}

sub create_client_exe {
    return unless $config->{client}->{build};
    chdir("$Bin/client");
    system("build-client-exe.bat");
    chdir($Bin);
    return;
}

sub create_installer {
    my $installer_folder = qq($Bin/installer);
    mkdir $installer_folder unless -d $installer_folder;

    my $innosetup_project = qq($installer_folder/innosetup.iss);

    my $template = <<'EOF';
[%- USE date -%]
[Setup]
AppName=[% product.name %] Site
AppVersion=[% product.version %]
AppVerName=[% product.name %] Site - [% product.version %]
AppPublisher=[% product.company %]
DefaultDirName={pf32}\[% product.company %]\[% product.name %] Site
DisableDirPage=yes
DefaultGroupName=[% product.company %]\[% product.name %] Site
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=[% installer %]
Compression=lzma/Max
SolidCompression=true
AppCopyright=(C) [% date.format( date.now, '%Y' ) %] [% product.company %]
TimeStampsInUTC=true
OutputManifestFile=innosetup.manifest
InternalCompressLevel=Max
ShowLanguageDialog=no
UninstallDisplayName=[% product.company %] - [% product.name %] Site
VersionInfoVersion=[% product.version %]
VersionInfoCompany=[% product.company %]
VersionInfoDescription=[% product.company %] - [% product.name %] Site Installer
VersionInfoTextVersion=[% product.company %] - [% product.name %] Site Installer [% product.version %]
VersionInfoCopyright=(C) [% date.format( date.now, '%Y' ) %] [% product.company %]
VersionInfoProductName=[% product.company %] - [% product.name %] Site
VersionInfoProductVersion=[% product.version %]
MinVersion=5.1.2600
PrivilegesRequired=admin
UsePreviousSetupType=false
UsePreviousTasks=false
UsePreviousAppDir=false
UsePreviousGroup=false
UsePreviousUserInfo=false
UsePreviousLanguage=false

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}";

[Files]
Source: ..\dist\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs restartreplace overwritereadonly uninsrestartdelete uninsremovereadonly replacesameversion 32bit; Excludes: ; 

[Run]
Filename: "{app}\[% output %].exe"; Parameters: "--install auto"; WorkingDir: {app}; Flags: RunHidden 32bit SkipIfDoesntExist; StatusMsg: "Installing service.... Please Wait"; 

[InstallDelete]
Type: files; Name: "{app}\*.log"

[UninstallRun]
Filename: "{app}\[% output %].exe"; Parameters: "--remove"; WorkingDir: {app}; Flags: RunHidden 32bit SkipIfDoesntExist; StatusMsg: "Removing service.... Please Wait"; 

[Icons]
Name: "{group}\[% product.name %] Client"; Filename: {app}\[% output.replace("site", "client") %].exe; WorkingDir: {app}; Flags: createonlyiffileexists;
Name: "{commondesktop}\[% product.name %] Client"; Filename: {app}\[% output.replace("site", "client") %].exe; WorkingDir: {app}; Tasks: desktopicon; Flags: createonlyiffileexists;
Name: "{group}\Program configuration"; Filename: {app}\program.ini; WorkingDir: {app};
Name: "{group}\{cm:UninstallProgram,[% product.name %]}"; Filename: "{uninstallexe}"

[INI]
Filename: {app}\program.ini; Section: "system"; Key: printer; String: {code:GetPrinterPath}

[Code]
var PrinterPathPage : TInputQueryWizardPage;

procedure InitializeWizard;

begin
PrinterPathPage := CreateInputQueryPage(
        wpWelcome,
        'Printer path information', 'Please enter the path to the network printer',
        '');
PrinterPathPage.Add( 'Printer', False );
end;

function PrinterPathForm_NextButtonClick( Page: TWizardPage ): Boolean;
begin
Result := True;
end;

function GetPrinterPath( Param: String ): string;
begin
Result := PrinterPathPage.Values[0];
end;
EOF

    my $tt = Template->new;
    $tt->process(
        \$template, {
            app       => \%app,
            installer => $installer,
            output    => $output,
            product   => \%product,
        },
        $innosetup_project
    );
    if ( $tt->error ) {
        die $tt->error;
    }
    else {
        log_message( "Created InnoSetup project file [$innosetup_project]",
            'debug' );
    }

    system( $innosetup, $innosetup_project ) == 0
      or do {
        log_message( 'Creating installer failed!', 'error' );
        die;
      };

    log_message( "Creating installer succeeded [$installer.exe]", 'info' );

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
            if ( -x $exe_path ) {
                log_message( "Found $compiler compiler at [$exe_path]\n",
                'debug' );
                return $exe_path if -x $exe_path;    
            }
            
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

@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!perl
#line 15

use 5.10.1;
use strict;
use warnings;
use utf8;
use Cwd;

$|++;

if ( not -r 'cpanfile' ) {
    my $cwd = getdcwd();
    say qq/Error: No cpanfile found in current directory [$cwd]!/;
}
else {
    system(qw/ ppm install App::cpanminus /);
    system(qw/ cpanm -n --installdeps .   /);
}

__END__
:endofperl
pause

#!perl

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

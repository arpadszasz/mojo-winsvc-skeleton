#!/usr/bin/env perl

use 5.10.1;
use strict;
use warnings;
use utf8;
use FindBin q($Bin);
use File::Slurp;
use Config::Tiny;
use Wx::Perl::Packager;
use Wx qw(:everything);
use Wx::Event qw(:everything);
use Wx::WebView;
use IO::Socket::PortState qw(check_ports);

my $config;
if ($PerlApp::VERSION) {
    $config = Config::Tiny->new->read_string( scalar read_file( \*DATA ) );
}
else {
    my $ini_file = "$Bin/../release.ini";
    die qq/Can't find configuration file [$ini_file]!/ unless $ini_file;
    $config = Config::Tiny->new->read($ini_file);
}

my $product_name = $config->{product}->{name};
my $address      = $config->{server}->{address} || 'localhost';
my $port         = $config->{server}->{port}    || 3000;
my $url          = qq(http://$address:$port);

exit 1 unless is_server_running();

my $app   = Wx::SimpleApp->new;
my $frame = Wx::Frame->new(
    undef, -1,
    $product_name . ' Client',
    wxDefaultPosition, wxDefaultSize,
    wxMINIMIZE_BOX | wxMAXIMIZE_BOX | wxCLOSE_BOX | wxSYSTEM_MENU | wxCAPTION
);

my $panel = Wx::Panel->new($frame);

my $sizer = Wx::BoxSizer->new(wxVERTICAL);

my $webview = Wx::WebView::New( $panel, wxID_ANY, $url );

if ( Wx::wxVERSION >= 2.009005 ) {
    $webview->EnableContextMenu(0);
}

$sizer->Add(
    $webview,
    1,
    wxEXPAND |
      wxALL,
    0
);

$panel->SetSizer($sizer);

EVT_CHAR_HOOK(
    $panel,
    sub {
        my $self    = shift;
        my $key_evt = shift;

        given ( my $key_code = $key_evt->GetKeyCode ) {
            when ( $key_code == Wx::WXK_ESCAPE ) { close_window() }
            when ( $key_code == Wx::WXK_F5 )     { reload_page() }
            when ( $key_code == Wx::WXK_F11 )    { toggle_fullscreen() }
            default {
                $key_evt->Skip
            }
        }
        return;
    }
);

EVT_CLOSE(
    $frame,
    \&close_window,
);

$frame->Show;
$frame->Maximize(1);
$app->SetTopWindow($frame);
$app->MainLoop;

exit 0;

sub is_server_running {
    my $check = check_ports(
        $address, 5,
        { tcp => { $port => { name => 'Mojo' } } }
    );

    if ( not $check->{tcp}->{ $config->{server}->{port} }->{open} ) {
        my $dialog = Wx::MessageDialog->new(
            $frame, ("Can not connect to $product_name Site!"),
            '',
            wxOK | wxICON_INFORMATION
        )->ShowModal;

        return;
    }

    return 1;
}

sub toggle_fullscreen {
    $frame->ShowFullScreen( $frame->IsFullScreen ? 0 : 1 );
    return;
}

sub reload_page {
    $webview->Reload();
    return;
}

sub close_window {
    my $dialog = Wx::MessageDialog->new(
        $frame, ("Do you want to close the client application?"),
        '',
        wxNO_DEFAULT | wxYES_NO | wxICON_QUESTION
    )->ShowModal;
    return if $dialog == wxID_NO;
    $frame->Destroy;
    return;
}

__DATA__

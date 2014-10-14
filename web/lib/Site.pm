package Site;

use DBI;

use Mojo::Base 'Mojolicious';

has 'dbh';
has 'ini_file';
has 'log_file';
has 'log_event';

sub startup {
    my $self = shift;

    if ($PerlSvc::VERSION) {
        my $temp_folder = PerlApp::get_temp_dir();
        $temp_folder =~ s/\\$//;
        push(
            @{ $self->renderer->paths },
            $temp_folder . '-' . $$ . '/templates'
        );

        if ( PerlSvc::RunningAsService() ) {
            $self->log(
                Mojo::Log->new( path => $self->log_file ),
                level => 'error'
            );
        }
    }

    if ( -r $self->ini_file ) {
        $self->plugin( 'INIConfig', { file => $self->ini_file } );
    }

    my $r = $self->routes;

    my $db = $r->bridge('/')->to(
        cb => sub {
            my $self = shift;

            # disable browser caching
            $self->res->headers->add(
                'Cache-control',
                'no-cache, no-store, max-age=0'
            );
            $self->res->headers->add( 'Pragma', 'no-cache' );
            $self->res->headers->add(
                'Expires',
                'Fri, 01 Jan 1990 00:00:00 GMT'
            );

            return 1;
        }
    );

    $db->get('/')->to( cb => sub { shift->render( text => "Service running!" ) } );
}
1;

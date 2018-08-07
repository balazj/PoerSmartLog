# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::WebUserAgent;

use strict;
use warnings;

use HTTP::Headers;
use List::Util qw(first);
use LWP::UserAgent;

use Kernel::System::Encode;
use Kernel::System::JSON;
use Kernel::System::Log;

=head1 NAME

Kernel::System::WebUserAgent - a web user agent lib

=head1 DESCRIPTION

All web user agent functions.

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    use Kernel::System::WebUserAgent;

    my $WebUserAgentObject = Kernel::System::WebUserAgent->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{LogObject} = Kernel::System::Log->new();

    $Self->{Timeout} = 15;

    return $Self;
}

=head2 Request()

return the content of requested URL.

Simple GET request:

    my %Response = $WebUserAgentObject->Request(
        URL => 'http://example.com/somedata.xml',
        NoLog               => 1, # (optional)
    );

Or a POST request; attributes can be a hashref like this:

    my %Response = $WebUserAgentObject->Request(
        URL  => 'http://example.com/someurl',
        Type => 'POST',
        Data => { Attribute1 => 'Value', Attribute2 => 'Value2' },
        NoLog               => 1, # (optional)
    );

alternatively, you can use an arrayref like this:

    my %Response = $WebUserAgentObject->Request(
        URL  => 'http://example.com/someurl',
        Type => 'POST',
        Data => [ Attribute => 'Value', Attribute => 'OtherValue' ],
        NoLog               => 1, # (optional)
    );

returns

    %Response = (
        Status  => '200 OK',    # http status
        Content => $ContentRef, # content of requested URL
    );

You can even pass some headers

    my %Response = $WebUserAgentObject->Request(
        URL    => 'http://example.com/someurl',
        Type   => 'POST',
        Data   => [ Attribute => 'Value', Attribute => 'OtherValue' ],
        Header => {
            Authorization => 'Basic xxxx',
            Content_Type  => 'text/json',
        },
        NoLog               => 1, # (optional)
    );

If you need to set credentials

    my %Response = $WebUserAgentObject->Request(
        URL          => 'http://example.com/someurl',
        Type         => 'POST',
        Data         => [ Attribute => 'Value', Attribute => 'OtherValue' ],
        Credentials  => {
            User     => 'user',
            Password => 'password',
            Realm    => 'realm',
            Location => 'ftp.server.org:80',
        },
        NoLog               => 1, # (optional)
    );

=cut

sub Request {
    my ( $Self, %Param ) = @_;

    # define method - default to GET
    $Param{Type} ||= 'GET';

    my $Response;

    # init agent
    my $UserAgent = LWP::UserAgent->new();

    # set credentials
    if ( $Param{Credentials} ) {
        my %CredentialParams    = %{ $Param{Credentials} || {} };
        my @Keys                = qw(Location Realm User Password);
        my $AllCredentialParams = !first { !defined $_ } @CredentialParams{@Keys};

        if ($AllCredentialParams) {

            $UserAgent->credentials(
                @CredentialParams{@Keys},
            );
        }
    }

    # set headers
    if ( $Param{Header} ) {
        $UserAgent->default_headers(
            HTTP::Headers->new( %{ $Param{Header} } ),
        );
    }

    # set timeout
    $UserAgent->timeout( $Self->{Timeout} );

    # set user agent
    $UserAgent->agent(
        'PoerSmart'
    );

    if ( $Param{Type} eq 'GET' ) {

        # perform get request on URL
        $Response = $UserAgent->get( $Param{URL} );
    }

    else {

        my $DataRef = ref $Param{Data};

        # check for Data param
        if ( $DataRef ne 'ARRAY' && $DataRef ne 'HASH' ) {

            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "WebUserAgent POST: Need Data param containing a hashref or arrayref with data."
            );
            return ( Status => 0 );
        }

        # perform post request plus data
        $Response = $UserAgent->post( $Param{URL}, $Param{Data} );
    }

    if ( !$Response->is_success() ) {

        if ( !$Param{NoLog} ) {

            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Can't perform $Param{Type} on $Param{URL}: " . $Response->status_line()
            );
        }

        return (
            Status => $Response->status_line(),
        );
    }

    # get the content to convert internal used charset
    my $ResponseContent = $Response->decoded_content();
    my $EncodeObject    = Kernel::System::Encode->new();
    $EncodeObject->EncodeInput( \$ResponseContent );

    if ( $Param{Return} && $Param{Return} eq 'REQUEST' ) {
        return (
            Status  => $Response->status_line(),
            Content => \$Response->request()->as_string(),
        );
    }

    # return request
    return (
        Status  => $Response->status_line(),
        Content => \$ResponseContent,
    );
}

1;

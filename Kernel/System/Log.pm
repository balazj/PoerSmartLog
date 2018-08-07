# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Log;

use strict;
use warnings;

use Kernel::System::Encode;

use Carp ();

=head1 NAME

Kernel::System::Log - global log interface

=head1 DESCRIPTION

All log functions.

=head1 PUBLIC INTERFACE

=head2 new()

create a log object.

    my $LogObject = Kernel::System::Log->new();

=cut

my %LogLevel = (
    error  => 16,
    notice => 8,
    info   => 4,
    debug  => 2,
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{ProductVersion} = 'PoerSmartLog';

    # check log prefix
    $Self->{LogPrefix} = $Param{LogPrefix} || '?LogPrefix?';

    # configured log level (debug by default)
    $Self->{MinimumLevel}    = 'debug';
    $Self->{MinimumLevel}    = lc $Self->{MinimumLevel};
    $Self->{MinimumLevelNum} = $LogLevel{ $Self->{MinimumLevel} };

    $Self->{LogFile} = 'poersmart.log';

    return $Self;
}

=head2 Log()

log something. log priorities are 'debug', 'info', 'notice' and 'error'.

These are mapped to the SysLog priorities. Please use the appropriate priority level:

=over

=item debug

Debug-level messages; info useful for debugging the application, not useful during operations.

=item info

Informational messages; normal operational messages - may be used for reporting etc, no action required.

=item notice

Normal but significant condition; events that are unusual but not error conditions, no immediate action required.

=item error

Error conditions. Non-urgent failures, should be relayed to developers or administrators, each item must be resolved.

=back

See for more info L<http://en.wikipedia.org/wiki/Syslog#Severity_levels>

    $LogObject->Log(
        Priority => 'error',
        Message  => "Need something!",
    );

=cut

sub Log {
    my ( $Self, %Param ) = @_;

    my $Priority    = lc $Param{Priority}  || 'debug';
    my $PriorityNum = $LogLevel{$Priority} || $LogLevel{debug};

    return 1 if $PriorityNum < $Self->{MinimumLevelNum};

    my $Message = $Param{MSG} || $Param{Message} || '???';
    my $Caller = $Param{Caller} || 0;

    # returns the context of the current subroutine and sub-subroutine!
    my ( $Package1, $Filename1, $Line1, $Subroutine1 ) = caller( $Caller + 0 );
    my ( $Package2, $Filename2, $Line2, $Subroutine2 ) = caller( $Caller + 1 );

    $Subroutine2 ||= $0;

    # log
    $Self->_Log(
        Priority  => $Priority,
        Message   => $Message,
        LogPrefix => $Self->{LogPrefix},
        Module    => $Subroutine2,
        Line      => $Line1,
    );

    # if error, write it to STDERR
    if ( $Priority =~ /^error/i ) {

        ## no critic
        my $Error = sprintf "ERROR: $Self->{LogPrefix} Perl: %vd OS: $^O Time: "
            . localtime() . "\n\n", $^V;
        ## use critic

        $Error .= " Message: $Message\n\n";

        if ( %ENV && ( $ENV{REMOTE_ADDR} || $ENV{REQUEST_URI} ) ) {

            my $RemoteAddress = $ENV{REMOTE_ADDR} || '-';
            my $RequestURI    = $ENV{REQUEST_URI} || '-';

            $Error .= " RemoteAddress: $RemoteAddress\n";
            $Error .= " RequestURI: $RequestURI\n\n";
        }

        $Error .= " Traceback ($$): \n";

        COUNT:
        for ( my $Count = 0; $Count < 30; $Count++ ) {

            my ( $Package1, $Filename1, $Line1, $Subroutine1 ) = caller( $Caller + $Count );

            last COUNT if !$Line1;

            my ( $Package2, $Filename2, $Line2, $Subroutine2 ) = caller( $Caller + 1 + $Count );

            # if there is no caller module use the file name
            $Subroutine2 ||= $0;

            # print line if upper caller module exists
            my $VersionString = '';

            eval { $VersionString = $Package1->VERSION || ''; };    ## no critic

            # version is present
            if ($VersionString) {
                $VersionString = ' (v' . $VersionString . ')';
            }

            $Error .= "   Module: $Subroutine2$VersionString Line: $Line1\n";

            last COUNT if !$Line2;
        }

        $Error .= "\n";
        print STDERR $Error;

        # store data (for the frontend)
        $Self->{error}->{Message}   = $Message;
        $Self->{error}->{Traceback} = $Error;
    }

    # remember to info and notice messages
    elsif ( lc $Priority eq 'info' || lc $Priority eq 'notice' ) {
        $Self->{ lc $Priority }->{Message} = $Message;
    }

    return 1;
}

sub _Log {
    my ( $Self, %Param ) = @_;

    my $FH;

    # open logfile
    ## no critic
    if ( !open $FH, '>>', $Self->{LogFile} ) {
        ## use critic

        # print error screen
        print STDERR "\n";
        print STDERR " >> Can't write $Self->{LogFile}: $! <<\n";
        print STDERR "\n";
        return;
    }

    my $EncodeObject = Kernel::System::Encode->new();

    # write log file
    $EncodeObject->ConfigureOutputFileHandle( FileHandle => $FH );

    print $FH '[' . localtime() . ']';    ## no critic

    if ( lc $Param{Priority} eq 'debug' ) {
        print $FH "[Debug][$Param{Module}][$Param{Line}] $Param{Message}\n";
    }
    elsif ( lc $Param{Priority} eq 'info' ) {
        print $FH "[Info][$Param{Module}] $Param{Message}\n";
    }
    elsif ( lc $Param{Priority} eq 'notice' ) {
        print $FH "[Notice][$Param{Module}] $Param{Message}\n";
    }
    elsif ( lc $Param{Priority} eq 'error' ) {
        print $FH "[Error][$Param{Module}][$Param{Line}] $Param{Message}\n";
    }
    else {

        # print error messages to STDERR
        print STDERR
            "[Error][$Param{Module}] Priority: '$Param{Priority}' not defined! Message: $Param{Message}\n";

        # and of course to logfile
        print $FH
            "[Error][$Param{Module}] Priority: '$Param{Priority}' not defined! Message: $Param{Message}\n";
    }

    # close file handle
    close $FH;

    return 1;
}


1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

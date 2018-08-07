# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Time;
## nofilter(TidyAll::Plugin::OTRS::Perl::Time)

use strict;
use warnings;

use Time::Local;
use Kernel::System::Log;

=head1 NAME

Kernel::System::Time - time functions

=head1 SYNOPSIS

This module is managing time functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create a time object.

    my $TimeObject = Kernel::System::Time;

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # 0=off; 1=on;
    $Self->{Debug} = 0;

    $Self->{TimeZone} = $Param{TimeZone}
        || $Param{UserTimeZone}
        || 0;
    $Self->{TimeSecDiff} = $Self->{TimeZone} * 3600;    # 60 * 60

    $Self->{LogObject} = Kernel::System::Log->new();

    return $Self;
}

=item SystemTime()

returns the number of non-leap seconds since what ever time the
system considers to be the epoch (that's 00:00:00, January 1, 1904
for Mac OS, and 00:00:00 UTC, January 1, 1970 for most other systems).

This will the time that the server considers to be the local time (based on
time zone configuration) plus the configured OTRS "TimeZone" diff (only recommended
for systems running in UTC).

    my $SystemTime = $TimeObject->SystemTime();

=cut

sub SystemTime {
    my $Self = shift;

    return time() + $Self->{TimeSecDiff};
}

=item SystemTime2TimeStamp()

returns a time stamp for a given system time in C<yyyy-mm-dd 23:59:59> format.

    my $TimeStamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $SystemTime,
    );

If you need the short format "23:59:59" for dates that are "today",
pass the Type parameter like this:

    my $TimeStamp = $TimeObject->SystemTime2TimeStamp(
        SystemTime => $SystemTime,
        Type       => 'Short',
    );

=cut

sub SystemTime2TimeStamp {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{SystemTime} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'Need SystemTime!'
        );
        return;
    }

    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = $Self->SystemTime2Date(%Param);
    if ( $Param{Type} && $Param{Type} eq 'Short' ) {
        my ( $CSec, $CMin, $CHour, $CDay, $CMonth, $CYear ) = $Self->SystemTime2Date(
            SystemTime => $Self->SystemTime(),
        );
        if ( $CYear == $Year && $CMonth == $Month && $CDay == $Day ) {
            return "$Hour:$Min:$Sec";
        }
        return "$Year-$Month-$Day $Hour:$Min:$Sec";
    }
    return "$Year-$Month-$Day $Hour:$Min:$Sec";
}

=item CurrentTimestamp()

returns a time stamp of the local system time (see L<SystemTime()>)
in C<yyyy-mm-dd 23:59:59> format.

    my $TimeStamp = $TimeObject->CurrentTimestamp();

=cut

sub CurrentTimestamp {
    my ( $Self, %Param ) = @_;

    return $Self->SystemTime2TimeStamp( SystemTime => $Self->SystemTime() );
}

=item SystemTime2Date()

converts a system time to a structured date array.

    my ($Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay) = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
    );

$WeekDay is the day of the week, with 0 indicating Sunday and 3 indicating Wednesday.

=cut

sub SystemTime2Date {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{SystemTime} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'Need SystemTime!'
        );
        return;
    }

    # get time format
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WDay ) = localtime $Param{SystemTime};    ## no critic
    $Year  += 1900;
    $Month += 1;
    $Month = sprintf "%02d", $Month;
    $Day   = sprintf "%02d", $Day;
    $Hour  = sprintf "%02d", $Hour;
    $Min   = sprintf "%02d", $Min;
    $Sec   = sprintf "%02d", $Sec;

    return ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WDay );
}

=item TimeStamp2SystemTime()

converts a given time stamp to local system time.

    my $SystemTime = $TimeObject->TimeStamp2SystemTime(
        String => '2004-08-14 22:45:00',
    );

=cut

sub TimeStamp2SystemTime {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{String} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'Need String!'
        );
        return;
    }

    my $SystemTime = 0;

    # match iso date format
    if ( $Param{String} =~ /(\d{4})-(\d{1,2})-(\d{1,2})\s(\d{1,2}):(\d{1,2}):(\d{1,2})/ ) {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $1,
            Month  => $2,
            Day    => $3,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match iso date format (wrong format)
    elsif ( $Param{String} =~ /(\d{1,2})-(\d{1,2})-(\d{4})\s(\d{1,2}):(\d{1,2}):(\d{1,2})/ ) {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $3,
            Month  => $2,
            Day    => $1,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match euro time format
    elsif ( $Param{String} =~ /(\d{1,2})\.(\d{1,2})\.(\d{4})\s(\d{1,2}):(\d{1,2}):(\d{1,2})/ ) {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $3,
            Month  => $2,
            Day    => $1,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match yyyy-mm-ddThh:mm:ss+tt:zz time format
    elsif (
        $Param{String}
        =~ /(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2}):(\d{1,2})(\+|\-)((\d{1,2}):(\d{1,2}))/i
        )
    {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $1,
            Month  => $2,
            Day    => $3,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # match mail time format
    elsif (
        $Param{String}
        =~ /((...),\s+|)(\d{1,2})\s(...)\s(\d{4})\s(\d{1,2}):(\d{1,2}):(\d{1,2})\s((\+|\-)(\d{2})(\d{2})|...)/
        )
    {
        my $DiffTime = 0;
        if ( $10 && $10 eq '+' ) {

            #            $DiffTime = $DiffTime - ($11 * 60 * 60);
            #            $DiffTime = $DiffTime - ($12 * 60);
        }
        elsif ( $10 && $10 eq '-' ) {

            #            $DiffTime = $DiffTime + ($11 * 60 * 60);
            #            $DiffTime = $DiffTime + ($12 * 60);
        }
        my @MonthMap    = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
        my $Month       = 1;
        my $MonthString = $4;
        for my $MonthCount ( 0 .. $#MonthMap ) {
            if ( $MonthString =~ /$MonthMap[$MonthCount]/i ) {
                $Month = $MonthCount + 1;
            }
        }
        $SystemTime = $Self->Date2SystemTime(
            Year   => $5,
            Month  => $Month,
            Day    => $3,
            Hour   => $6,
            Minute => $7,
            Second => $8,
        ) + $DiffTime + $Self->{TimeSecDiff};
    }
    elsif (    # match yyyy-mm-ddThh:mm:ssZ
        $Param{String} =~ /(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2}):(\d{1,2})Z$/
        )
    {
        $SystemTime = $Self->Date2SystemTime(
            Year   => $1,
            Month  => $2,
            Day    => $3,
            Hour   => $4,
            Minute => $5,
            Second => $6,
        );
    }

    # return error
    if ( !defined $SystemTime ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Invalid Date '$Param{String}'!"
        );
        return;
    }

    # return system time
    return $SystemTime;

}

=item Date2SystemTime()

converts a structured date array to local system time.

    my $SystemTime = $TimeObject->Date2SystemTime(
        Year   => 2004,
        Month  => 8,
        Day    => 14,
        Hour   => 22,
        Minute => 45,
        Second => 0,
    );

=cut

sub Date2SystemTime {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(Year Month Day Hour Minute Second)) {
        if ( !defined $Param{$_} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }
    my $SystemTime = eval {
        timelocal(
            $Param{Second}, $Param{Minute}, $Param{Hour}, $Param{Day}, ( $Param{Month} - 1 ),
            $Param{Year}
        );
    };

    if ( !defined $SystemTime ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Invalid Date '$Param{Year}-$Param{Month}-$Param{Day} $Param{Hour}:$Param{Minute}:$Param{Second}'!"
        );
        return;
    }

    return $SystemTime;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

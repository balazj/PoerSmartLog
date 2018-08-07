# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PoerSmart;

use strict;
use warnings;

use Kernel::System::DB;
use Kernel::System::File;
use Kernel::System::Time;
use Kernel::System::WebUserAgent;
use Kernel::System::XML;

sub new {
    my ( $Type, %Param ) = @_;

    # Allocate new hash for object.
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{LogObject} = Kernel::System::Log->new();

    return $Self;
}

=item ParametersGet()

Get current heating parameters (using web).

    my @Result = $PoerSmartObject->ParametersGet();

Returns:
    @Result = [
        {
            "ActionFlag" => 5,
            "BackWorkMode" => 3,
            "BatteryPercent" => 82,
            "CurTemperature" => "16.9",
            "DisplayMode" => 0,
            "EcoTemprature" => 9,
            "EnergySaveing" => 0,
            "Frequency" => "868M",
            "GatewayId" => "280274838347305",
            "HardVersion" => "v1.0",
            "HolidayEnable" => 0,
            "HolidayEnd" => 0,
            "HolidayIsOpen" => 0,
            "HolidayStart" => 0,
            "Humidity" => 63,
            "Id" => "278075812094621",
            "LocateId" => 7544,
            "MakePowerPercent" => 6,
            "ManTemprature" => 9,
            "NodeName" => "fce89200229d",
            "NodeSN" => "fce89200229d",
            "NodeType" => 0,
            "OffTemprature" => 5,
            "OverrideIsOpen" => 0,
            "OverrideTemperature" => 17,
            "OverrideTime" => 0,
            "RfLinkActuator" => 1,
            "RfLinkGateway" => 1,
            "SoftVersion" => "v2.0",
            "SptTemprature" => 17,
            "VoltCap" => 0,
            "VoltTrl" => 1105,
            "WindowOpen" => 0,
            "WorkMode" => 0,
            "WriteStatus" => 1,
        },
        ...
    ];


=cut

sub ParametersGet {
    my ( $Self, %Param ) = @_;

    # Get needed objects.
    my $XMLObject = Kernel::System::XML->new();
    my $FileObject = Kernel::System::File->new();
    my $WebUserAgentObject = Kernel::System::WebUserAgent->new();

    # Read file content.
    my $ContentSCALARRef = $FileObject->FileRead(
        Location        => 'Kernel/Config/Settings.xml',
    );

    # Parse XML.
    my @XML = $XMLObject->XMLParse( String => $$ContentSCALARRef );

    my %ConnectionData;
    
    # Get ConnectionData from XML file.
    for my $Needed (qw(Email Password URL Realm Location)) {

        ITEM:
        for my $Item (@XML) {
            if ($Item->{Tag} eq 'Setting' && $Item->{Name} && $Item->{Name} eq $Needed) {
                $ConnectionData{$Needed} = $Item->{Content};
                last ITEM;
            }
        }
    }

    my %Response = $WebUserAgentObject->Request(
        URL  => $ConnectionData{URL},
        Type         => 'GET',
        Data         => [  ],
        Credentials  => {
            User     => $ConnectionData{Email},
            Password => $ConnectionData{Password},
            Realm    => $ConnectionData{Realm},
            Location => $ConnectionData{Location},
        },
        NoLog               => 1,
    );

    if ($Response{Status} ne '200 OK') {

        # Something went wrong.
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => $Response{Status}
        );
        return;
    }

    my $JSONObject = Kernel::System::JSON->new();

    # Trim response.
    my $Content = $Self->_StringClean(
        StringRef => $Response{Content},
        TrimLeft  => 1,
        TrimRight => 1,
        RemoveAllNewlines => 1,
    );
    
    my $PerlStructure = $JSONObject->Decode(
        Data => $$Content,
    );

    for my $ArrayItem (@{$PerlStructure}) {

        # Calculate temperature values in Celzius degrees.
        for my $Item (qw(CurTemperature EcoTemprature ManTemprature OffTemprature OverrideTemperature SptTemprature)) {
            $ArrayItem->{$Item} = $ArrayItem->{$Item} / 90;
        }
    }

    return @{$PerlStructure};
}

sub LogAdd {
    my ( $Self, %Param ) = @_;

    # Check needed stuff.
    for my $Needed (qw(Data)) {
        if ( !$Param{$Needed} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Needed $Needed!\n"
            );
            return;
        }
    }

    my $DBObject = Kernel::System::DB->new();

    my $SQL = '
        INSERT INTO Log
            ( 
                ActionFlag, BackWorkMode, BatteryPercent, CurTemperature, DisplayMode,
                EcoTemprature, EnergySaveing, Frequency, GatewayId, HardVersion, HolidayEnable,
                HolidayEnd, HolidayIsOpen, HolidayStart, Humidity, DeviceID, LocateId,
                MakePowerPercent, ManTemprature, NodeName, NodeSN, NodeType, OffTemprature,
                OverrideIsOpen, OverrideTemperature, OverrideTime, RfLinkActuator, RfLinkGateway,
                SoftVersion, SptTemprature, VoltCap, VoltTrl, WindowOpen, WorkMode, WriteStatus
            )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?)
    ';

    # create db record
    return if !$DBObject->Do(
        SQL  => $SQL,
        Bind => [
            \$Param{Data}->{ActionFlag},
            \$Param{Data}->{BackWorkMode},
            \$Param{Data}->{BatteryPercent},
            \$Param{Data}->{CurTemperature},
            \$Param{Data}->{DisplayMode},
            \$Param{Data}->{EcoTemprature},
            \$Param{Data}->{EnergySaveing},
            \$Param{Data}->{Frequency},
            \$Param{Data}->{GatewayId},
            \$Param{Data}->{HardVersion},
            \$Param{Data}->{HolidayEnable},
            \$Param{Data}->{HolidayEnd},
            \$Param{Data}->{HolidayIsOpen},
            \$Param{Data}->{HolidayStart},
            \$Param{Data}->{Humidity},
            \$Param{Data}->{Id},
            \$Param{Data}->{LocateId},
            \$Param{Data}->{MakePowerPercent},
            \$Param{Data}->{ManTemprature},
            \$Param{Data}->{NodeName},
            \$Param{Data}->{NodeSN},
            \$Param{Data}->{NodeType},
            \$Param{Data}->{OffTemprature},
            \$Param{Data}->{OverrideIsOpen},
            \$Param{Data}->{OverrideTemperature},
            \$Param{Data}->{OverrideTime},
            \$Param{Data}->{RfLinkActuator},
            \$Param{Data}->{RfLinkGateway},
            \$Param{Data}->{SoftVersion},
            \$Param{Data}->{SptTemprature},
            \$Param{Data}->{VoltCap},
            \$Param{Data}->{VoltTrl},
            \$Param{Data}->{WindowOpen},
            \$Param{Data}->{WorkMode},
            \$Param{Data}->{WriteStatus},
        ],
    );

    return 1;
}

=head2 _StringClean()

clean a given string

    my $StringRef = $Self->_StringClean(
        StringRef         => \'String',
        TrimLeft          => 0,  # (optional) default 1
        TrimRight         => 0,  # (optional) default 1
        RemoveAllNewlines => 1,  # (optional) default 0
        RemoveAllTabs     => 1,  # (optional) default 0
        RemoveAllSpaces   => 1,  # (optional) default 0
    );

=cut

sub _StringClean {
    my ( $Self, %Param ) = @_;

    if ( !$Param{StringRef} || ref $Param{StringRef} ne 'SCALAR' ) {

        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => 'Need a scalar reference!',
        );
        return;
    }

    return $Param{StringRef} if !defined ${ $Param{StringRef} };
    return $Param{StringRef} if ${ $Param{StringRef} } eq '';

    # check for invalid utf8 characters and remove invalid strings
    if ( !utf8::valid( ${ $Param{StringRef} } ) ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Removed string containing invalid utf8: '${ $Param{StringRef} }'!"
        );

        ${ $Param{StringRef} } = '';
        return;
    }

    # set default values
    $Param{TrimLeft}  = defined $Param{TrimLeft}  ? $Param{TrimLeft}  : 1;
    $Param{TrimRight} = defined $Param{TrimRight} ? $Param{TrimRight} : 1;

    my %TrimAction = (
        RemoveAllNewlines => qr{ [\n\r\f] }xms,
        RemoveAllTabs     => qr{ \t       }xms,
        RemoveAllSpaces   => qr{ [ ]      }xms,
        TrimLeft          => qr{ \A \s+   }xms,
        TrimRight         => qr{ \s+ \z   }xms,
    );

    ACTION:
    for my $Action ( sort keys %TrimAction ) {
        next ACTION if !$Param{$Action};

        ${ $Param{StringRef} } =~ s{ $TrimAction{$Action} }{}xmsg;
    }

    return $Param{StringRef};
}


1;
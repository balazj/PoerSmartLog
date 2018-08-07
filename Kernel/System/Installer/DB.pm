# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Installer::DB;

use strict;
use warnings;

use Kernel::System::DB;

=head1 NAME

Kernel::System::Installer::DB - object

=head1 DESCRIPTION

All installer DB functions.

=head1 PUBLIC INTERFACE

=head2 new()

create new object.

    my $InstallerObject = Kernel::System::Installer->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my %Result = (
        Success => 0,
    );

    # Create needed objects.
    my $DBObject = Kernel::System::DB->new(
        Install => 1,
    );

    my $DBName = $DBObject->{DBName};

    my @Commands = (
        {
            Fetch => {
                SQL => 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ?',
                Bind => [ \$DBName ],
            },
        },
        {
            Do => {
                SQL => "CREATE DATABASE $DBName DEFAULT CHARSET=utf8",
                Bind => [],
            },
        },
        {
            CreateDBObject => 1,
        },
        {
            Do => {
                SQL => '
                    CREATE TABLE Log (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        ActionFlag TINYINT,
                        BackWorkMode TINYINT,
                        BatteryPercent TINYINT,
                        CurTemperature FLOAT,
                        DisplayMode TINYINT,
                        EcoTemprature TINYINT,
                        EnergySaveing TINYINT,
                        Frequency VARCHAR(5),
                        GatewayId VARCHAR(17),
                        HardVersion VARCHAR(10),
                        HolidayEnable TINYINT(1),
                        HolidayEnd TINYINT,
                        HolidayIsOpen TINYINT(1),
                        HolidayStart TINYINT,
                        Humidity TINYINT,
                        DeviceID VARCHAR(17),
                        LocateId INT,
                        MakePowerPercent TINYINT,
                        ManTemprature FLOAT,
                        NodeName CHAR(12),
                        NodeSN CHAR(12),
                        NodeType TINYINT,
                        OffTemprature FLOAT,
                        OverrideIsOpen TINYINT,
                        OverrideTemperature FLOAT,
                        OverrideTime TINYINT,
                        RfLinkActuator TINYINT,
                        RfLinkGateway TINYINT,
                        SoftVersion VARCHAR(10),
                        SptTemprature FLOAT,
                        VoltCap TINYINT,
                        VoltTrl SMALLINT,
                        WindowOpen TINYINT,
                        WorkMode TINYINT,
                        WriteStatus TINYINT,
                        TimeStamp DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                '
            },
        },
    );

    COMMAND:
    for my $Command (@Commands) {

        if ($Command->{Fetch}) {
            
            # db query
            return if !$DBObject->Prepare(
                SQL  => $Command->{Fetch}->{SQL},
                Bind => $Command->{Fetch}->{Bind},
            );
        
            while ( my @Row = $DBObject->FetchrowArray() ) {
                if ($Row[0]) {
                    print "\n        Database already exists!";
                    last COMMAND;
                }
            }
        }
        elsif ($Command->{Do}) {

            exit 2 if !$DBObject->Do(
                SQL  => $Command->{Do}->{SQL},
                Bind => $Command->{Do}->{Bind},
            );
        }
        elsif ($Command->{CreateDBObject}) {
            $DBObject = Kernel::System::DB->new();
        }
    }

    $Result{Success} = 1;
    return %Result;
}


1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

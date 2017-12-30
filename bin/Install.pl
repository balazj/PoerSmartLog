#!/usr/bin/perl
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
# --

use strict;
use warnings;

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';

use Kernel::System::DB;

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
                print "Database already exists!\n";
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
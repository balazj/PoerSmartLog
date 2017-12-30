# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::DB;

use strict;
use warnings;

use DBI;
use List::Util();

use Kernel::System::Encode;
use Kernel::System::File;
use Kernel::System::Time;
use Kernel::System::XML;
=head1 NAME

Kernel::System::DB - global database interface

=head1 DESCRIPTION

All database functions to connect/insert/update/delete/... to a database.

=head1 PUBLIC INTERFACE

=head2 new()

create database object, with database connect..
Usually you do not use it directly, instead use:

    my $DBObject = Kernel::System::DB->new(
            DatabaseDSN  => 'DBI:mysql:database=db_name;host=localhost;',
            Install => 1,
            Attribute => {
                LongTruncOk => 1,
                LongReadLen => 100*1024,
            },
        },
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # 0=off; 1=updates; 2=+selects; 3=+Connects;
    $Self->{Debug} = $Param{Debug} || 0;

    my $XMLObject = Kernel::System::XML->new();
    my $FileObject = Kernel::System::File->new();

    # Read file content.
    my $ContentSCALARRef = $FileObject->FileRead(
        Location        => 'Kernel/Config/Database.xml',
    );

    # Parse XML.
    my @XML = $XMLObject->XMLParse( String => $$ContentSCALARRef );
    
    # Get data from XML file.
    for my $Needed (qw(DSN USER PW)) {

        ITEM:
        for my $Item (@XML) {
            if ($Item->{Tag} eq 'Setting' && $Item->{Name} && $Item->{Name} eq $Needed) {
                $Self->{$Needed} = $Item->{Content};
                last ITEM;
            }
        }
    }

    $Self->{DSN} =~ m{database=(.*?);};
    $Self->{DBName} = $1;

    if ($Param{Install}) {
        $Self->{OriginalDSN} = $Self->{DSN};
        $Self->{DSN} =~ s{database=.*?;}{database=;}s;
    }

    # get database type (auto detection)
    $Self->{'DB::Type'} = 'mysql';

    # set database functions
    $Self->LoadPreferences();

    return $Self;
}

=head2 Connect()

to connect to a database

    $DBObject->Connect();

=cut

sub Connect {
    my $Self = shift;

    # check database handle
    if ( $Self->{dbh} ) {

        my $PingTimeout = 10;        # Only ping every 10 seconds (see bug#12383).
        my $CurrentTime = time();    ## no critic

        if ( $CurrentTime - ( $Self->{LastPingTime} // 0 ) < $PingTimeout ) {
            return $Self->{dbh};
        }

        # Ping to see if the connection is still alive.
        if ( $Self->{dbh}->ping() ) {
            $Self->{LastPingTime} = $CurrentTime;
            return $Self->{dbh};
        }

        # Ping failed: cause a reconnect.
        delete $Self->{dbh};
    }

    # debug
    if ( $Self->{Debug} > 2 ) {
        # TODO: Log.
        print "DB.pm->Connect: DSN: $Self->{DSN}, User: $Self->{USER}, Pw: $Self->{PW}, DB Type: $Self->{'DB::Type'};";
    }

    # db connect
    $Self->{dbh} = DBI->connect(
        $Self->{DSN},
        $Self->{USER},
        $Self->{PW},
        $Self->{'DB::Attribute'},
    );

    if ( !$Self->{dbh} ) {
        # TODO: Log.

        print $DBI::errstr;
        return;
    }

    if ( $Self->{'DB::Connect'} ) {
        $Self->Do( SQL => $Self->{'DB::Connect'} );
    }

    return $Self->{dbh};
}

=head2 Disconnect()

to disconnect from a database

    $DBObject->Disconnect();

=cut

sub Disconnect {
    my $Self = shift;

    # debug
    if ( $Self->{Debug} > 2 ) {
        # TODO: Log.

        print 'DB.pm->Disconnect';
    }

    # do disconnect
    if ( $Self->{dbh} ) {
        $Self->{dbh}->disconnect();
        delete $Self->{dbh};
    }

    return 1;
}

=head2 Error()

to retrieve database errors

    my $ErrorMessage = $DBObject->Error();

=cut

sub Error {
    my $Self = shift;

    return $DBI::errstr;
}

=head2 Do()

to insert, update or delete values

    $DBObject->Do( SQL => "INSERT INTO table (name) VALUES ('dog')" );

    $DBObject->Do( SQL => "DELETE FROM table" );

    you also can use DBI bind values (used for large strings):

    my $Var1 = 'dog1';
    my $Var2 = 'dog2';

    $DBObject->Do(
        SQL  => "INSERT INTO table (name1, name2) VALUES (?, ?)",
        Bind => [ \$Var1, \$Var2 ],
    );

=cut

sub Do {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{SQL} ) {
        # TODO: Log.
        print 'Need SQL!';
        return;
    }

    if ( $Self->{'DB::PreProcessSQL'} ) {
        $Self->PreProcessSQL( \$Param{SQL} );
    }

    # check bind params
    my @Array;
    if ( $Param{Bind} ) {
        for my $Data ( @{ $Param{Bind} } ) {
            if ( ref $Data eq 'SCALAR' ) {
                push @Array, $$Data;
            }
            else {
                # TODO: Log.
                print 'No SCALAR param in Bind!';
                return;
            }
        }
        if ( @Array && $Self->{'DB::PreProcessBindData'} ) {
            $Self->PreProcessBindData( \@Array );
        }
    }

    # Replace current_timestamp with real time stamp.
    # - This avoids time inconsistencies of app and db server
    # - This avoids timestamp problems in Postgresql servers where
    #   the timestamp is sometimes 1 second off the perl timestamp.
    my $Timestamp = Kernel::System::Time->new()->CurrentTimestamp();
     $Param{SQL} =~ s{
        (?<= \s | \( | , )  # lookahead
        current_timestamp   # replace current_timestamp by 'yyyy-mm-dd hh:mm:ss'
        (?=  \s | \) | , )  # lookbehind
    }
    {
        '$Timestamp'
    }xmsg;

    # debug
    if ( $Self->{Debug} > 0 ) {
        $Self->{DoCounter}++;

        # TODO: Log.
        print "DB.pm->Do ($Self->{DoCounter}) SQL: '$Param{SQL}'";
    }

    return if !$Self->Connect();

    # send sql to database
    if ( !$Self->{dbh}->do( $Param{SQL}, undef, @Array ) ) {
        # TODO: Log.
        print "$DBI::errstr, SQL: '$Param{SQL}'";
        return;
    }

    return 1;
}

=head2 Prepare()

to prepare a SELECT statement

    $DBObject->Prepare(
        SQL   => "SELECT id, name FROM table",
        Limit => 10,
    );

or in case you want just to get row 10 until 30

    $DBObject->Prepare(
        SQL   => "SELECT id, name FROM table",
        Start => 10,
        Limit => 20,
    );

in case you don't want utf-8 encoding for some columns, use this:

    $DBObject->Prepare(
        SQL    => "SELECT id, name, content FROM table",
        Encode => [ 1, 1, 0 ],
    );

you also can use DBI bind values, required for large strings:

    my $Var1 = 'dog1';
    my $Var2 = 'dog2';

    $DBObject->Prepare(
        SQL    => "SELECT id, name, content FROM table WHERE name_a = ? AND name_b = ?",
        Encode => [ 1, 1, 0 ],
        Bind   => [ \$Var1, \$Var2 ],
    );

=cut

sub Prepare {
    my ( $Self, %Param ) = @_;

    my $SQL   = $Param{SQL};
    my $Limit = $Param{Limit} || '';
    my $Start = $Param{Start} || '';

    # check needed stuff
    if ( !$Param{SQL} ) {
        # TODO: Log.
        print 'Need SQL!';
        return;
    }

    if ( $Param{Bind} && ref $Param{Bind} ne 'ARRAY' ) {
        # TODO: Log.
        print 'Bind must be and array reference!';
    }

    if ( defined $Param{Encode} ) {
        $Self->{Encode} = $Param{Encode};
    }
    else {
        $Self->{Encode} = undef;
    }
    $Self->{Limit}        = 0;
    $Self->{LimitStart}   = 0;
    $Self->{LimitCounter} = 0;

    # build final select query
    if ($Limit) {
        if ($Start) {
            $Limit = $Limit + $Start;
            $Self->{LimitStart} = $Start;
        }
        if ( $Self->{'DB::Limit'} eq 'limit' ) {
            $SQL .= " LIMIT $Limit";
        }
        elsif ( $Self->{'DB::Limit'} eq 'top' ) {
            $SQL =~ s{ \A \s* (SELECT ([ ]DISTINCT|)) }{$1 TOP $Limit}xmsi;
        }
        else {
            $Self->{Limit} = $Limit;
        }
    }

    # debug
    if ( $Self->{Debug} > 1 ) {
        $Self->{PrepareCounter}++;
        # TODO: Log.
        print "DB.pm->Prepare ($Self->{PrepareCounter}/" . time() . ") SQL: '$SQL'";
    }

    # slow log feature
    my $LogTime;
    if ( $Self->{SlowLog} ) {
        $LogTime = time();
    }

    if ( $Self->{'DB::PreProcessSQL'} ) {
        $Self->PreProcessSQL( \$SQL );
    }

    # check bind params
    my @Array;
    if ( $Param{Bind} ) {
        for my $Data ( @{ $Param{Bind} } ) {
            if ( ref $Data eq 'SCALAR' ) {
                push @Array, $$Data;
            }
            else {
                # TODO: Log.
                print 'No SCALAR param in Bind!';
                return;
            }
        }
        if ( @Array && $Self->{'DB::PreProcessBindData'} ) {
            $Self->PreProcessBindData( \@Array );
        }
    }

    return if !$Self->Connect();

    # do
    if ( !( $Self->{Cursor} = $Self->{dbh}->prepare($SQL) ) ) {
        # TODO: Log.
        print "$DBI::errstr, SQL: '$SQL'";
        return;
    }

    if ( !$Self->{Cursor}->execute(@Array) ) {
        # TODO: Log.
        print "$DBI::errstr, SQL: '$SQL'";
        return;
    }

    # slow log feature
    if ( $Self->{SlowLog} ) {
        my $LogTimeTaken = time() - $LogTime;
        if ( $LogTimeTaken > 4 ) {
            # TODO: Log.
            print "Slow ($LogTimeTaken s) SQL: '$SQL'";
        }
    }

    return 1;
}

=head2 FetchrowArray()

to process the results of a SELECT statement

    $DBObject->Prepare(
        SQL   => "SELECT id, name FROM table",
        Limit => 10
    );

    while (my @Row = $DBObject->FetchrowArray()) {
        print "$Row[0]:$Row[1]\n";
    }

=cut

sub FetchrowArray {
    my $Self = shift;

    # work with cursors if database don't support limit
    if ( !$Self->{'DB::Limit'} && $Self->{Limit} ) {
        if ( $Self->{Limit} <= $Self->{LimitCounter} ) {
            $Self->{Cursor}->finish();
            return;
        }
        $Self->{LimitCounter}++;
    }

    # fetch first not used rows
    if ( $Self->{LimitStart} ) {
        for ( 1 .. $Self->{LimitStart} ) {
            if ( !$Self->{Cursor}->fetchrow_array() ) {
                $Self->{LimitStart} = 0;
                return ();
            }
            $Self->{LimitCounter}++;
        }
        $Self->{LimitStart} = 0;
    }

    # return
    my @Row = $Self->{Cursor}->fetchrow_array();

    if ( !$Self->{'DB::Encode'} ) {
        return @Row;
    }

    # get encode object
    my $EncodeObject = Kernel::System::Encode->new();

    # e. g. set utf-8 flag
    my $Counter = 0;
    ELEMENT:
    for my $Element (@Row) {

        next ELEMENT if !defined $Element;

        if ( !defined $Self->{Encode} || ( $Self->{Encode} && $Self->{Encode}->[$Counter] ) ) {
            $EncodeObject->EncodeInput( \$Element );
        }
    }
    continue {
        $Counter++;
    }

    return @Row;
}

=head2 Ping()

checks if the database is reachable

    my $Success = $DBObject->Ping(
        AutoConnect => 0,  # default 1
    );

=cut

sub Ping {
    my ( $Self, %Param ) = @_;

    # debug
    if ( $Self->{Debug} > 2 ) {
        # TODO: Log.
        print 'DB.pm->Ping';
    }

    if ( !defined $Param{AutoConnect} || $Param{AutoConnect} ) {
        return if !$Self->Connect();
    }
    else {
        return if !$Self->{dbh};
    }

    return $Self->{dbh}->ping();
}


sub LoadPreferences {
    my ( $Self, %Param ) = @_;

    # db settings
    $Self->{'DB::Limit'}                = 'limit';
    $Self->{'DB::DirectBlob'}           = 1;
    $Self->{'DB::QuoteSingle'}          = '\\';
    $Self->{'DB::QuoteBack'}            = '\\';
    $Self->{'DB::QuoteSemicolon'}       = '\\';
    $Self->{'DB::QuoteUnderscoreStart'} = '\\';
    $Self->{'DB::QuoteUnderscoreEnd'}   = '';
    $Self->{'DB::CaseSensitive'}        = 0;
    $Self->{'DB::LikeEscapeString'}     = '';

    # mysql needs to proprocess the data to fix UTF8 issues
    $Self->{'DB::PreProcessSQL'}      = 1;
    $Self->{'DB::PreProcessBindData'} = 1;

    # how to determine server version
    # version can have package prefix, we need to extract that
    # example of VERSION() output: '5.5.32-0ubuntu0.12.04.1'
    # if VERSION() contains 'MariaDB', add MariaDB, otherwise MySQL.
    $Self->{'DB::Version'}
        = "SELECT CONCAT( IF (INSTR( VERSION(),'MariaDB'),'MariaDB ','MySQL '), SUBSTRING_INDEX(VERSION(),'-',1))";

    $Self->{'DB::ListTables'} = 'SHOW TABLES';

    # DBI/DBD::mysql attributes
    # disable automatic reconnects as they do not execute DB::Connect, which will
    # cause charset problems
    $Self->{'DB::Attribute'} = {
        mysql_auto_reconnect => 0,
    };

    # set current time stamp if different to "current_timestamp"
    $Self->{'DB::CurrentTimestamp'} = '';

    # set encoding of selected data to utf8
    $Self->{'DB::Encode'} = 1;

    # shell setting
    $Self->{'DB::Comment'}     = '# ';
    $Self->{'DB::ShellCommit'} = ';';

    #$Self->{'DB::ShellConnect'} = '';

    # init sql setting on db connect
    $Self->{'DB::Connect'} = 'SET NAMES utf8';

    return 1;
}

sub PreProcessBindData {
    my ( $Self, $BindRef ) = @_;

    my $Size = scalar @{ $BindRef // [] };

    my $EncodeObject = Kernel::System::Encode->new();

    for ( my $I = 0; $I < $Size; $I++ ) {

        $Self->_FixMysqlUTF8( \$BindRef->[$I] );

        $EncodeObject->EncodeOutput( \$BindRef->[$I] );
    }
    return;
}

sub PreProcessSQL {
    my ( $Self, $SQLRef ) = @_;
    $Self->_FixMysqlUTF8($SQLRef);
    my $EncodeObject = Kernel::System::Encode->new();
    $EncodeObject->EncodeOutput($SQLRef);
    return;
}

=begin Internal:

=cut

# Replace any unicode characters that need more than three bytes in UTF8
#   with the unicode replacement character. MySQL's utf8 encoding only
#   supports three bytes. In future we might want to use utf8mb4 (supported
#   since 5.5.3+), but that will lead to problems with key sizes on mysql.
# See also http://mathiasbynens.be/notes/mysql-utf8mb4.
sub _FixMysqlUTF8 {
    my ( $Self, $StringRef ) = @_;

    return if !$$StringRef;
    return if !Encode::is_utf8($$StringRef);

    $$StringRef =~ s/([\x{10000}-\x{10FFFF}])/"\x{FFFD}"/eg;

    return;
}

sub DESTROY {
    my $Self = shift;

    # cleanup open statement handle if there is any and then disconnect from DB
    if ( $Self->{Cursor} ) {
        $Self->{Cursor}->finish();
    }
    $Self->Disconnect();

    return 1;
}

1;

=end Internal:

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

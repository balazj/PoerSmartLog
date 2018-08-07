# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::File;

use strict;
use warnings;

use Kernel::System::Log;

use Fcntl qw(:flock);

=head1 NAME

Kernel::System::File - object

=head1 DESCRIPTION

All File functions.

=head1 PUBLIC INTERFACE

=head2 new()

create new object.

    my $FileObject = Kernel::System::File->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{LogObject} = Kernel::System::Log->new();

    return $Self;
}

=head2 FileRead()

Read files from file system.

    my $ContentSCALARRef = $FileObject->FileRead(
        Location        => 'c:\some\location\file2read.txt',

        Mode            => 'binmode', # optional - binmode|utf8
        Type            => 'Local',   # optional - Local|Attachment|MD5
        Result          => 'SCALAR',  # optional - SCALAR|ARRAY
    );

=cut

sub FileRead {
    my ( $Self, %Param ) = @_;

    my $FH;

    # filename clean up
    $Param{Location} =~ s{//}{/}xmsg;

    # set open mode
    my $Mode = '<';
    if ( $Param{Mode} && $Param{Mode} =~ m{ \A utf-?8 \z }xmsi ) {
        $Mode = '<:utf8';
    }

    # return if file can not open
    if ( !open $FH, $Mode, $Param{Location} ) {    ## no critic
        my $Error = $!;

        # Check if file exists only if system was not able to open it (to get better error message).
        if ( !-e $Param{Location} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "$Param{Location} doesn't exists.",
            );
            return;
        }
        else {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Unable to open $Param{Location}.",
            );
            return;
        }
        return;
    }

    # lock file (Shared Lock)
    if ( !flock $FH, LOCK_SH ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Unable to lock $Param{Location}."
        );
        return;
    }

    # enable binmode
    if ( !$Param{Mode} || $Param{Mode} =~ m{ \A binmode }xmsi ) {
        binmode $FH;
    }

    # read file as array
    if ( $Param{Result} && $Param{Result} eq 'ARRAY' ) {

        # read file content at once
        my @Array = <$FH>;
        close $FH;

        return \@Array;
    }

    # read file as string
    my $String = do { local $/; <$FH> };
    close $FH;

    return \$String;
}

=head2 Require()

Require/load a module.

    my $Loaded = $FileObject->Require(
        'Kernel::System::Example',
        Silent => 1,                # optional, no log entry if module was not found
    );

=cut

sub Require {
    my ( $Self, $Module, %Param ) = @_;

    if ( !$Module ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need module!',
        );
        return;
    }

    eval {
        my $FileName = $Module =~ s{::}{/}smxgr;
        require $FileName . '.pm';
    };

    # Handle errors.
    if ($@) {

        if ( !$Param{Silent} ) {
            my $Message = $@;
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Caller   => 1,
                Priority => 'error',
                Message  => $Message,
            );
        }

        return;
    }

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

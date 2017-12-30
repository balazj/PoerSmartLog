# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::File;

use strict;
use warnings;

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
            print "$Param{Location} doesn't exists.\n";

            # TODO: Log.
        }
        else {
            print "Unable to open $Param{Location}.\n";

            # TODO: Log.
        }
        return;
    }

    # lock file (Shared Lock)
    if ( !flock $FH, LOCK_SH ) {
        print "Unable to lock $Param{Location}.\n";

        # TODO: Log.
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

1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

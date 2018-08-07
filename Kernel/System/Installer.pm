# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Installer;

use strict;
use warnings;

use Kernel::System::File;

=head1 NAME

Kernel::System::Installer - object

=head1 DESCRIPTION

All installer functions.

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

sub Install {
    my ( $Self, %Param ) = @_;

    print "\nInstallation started.";

    my $FileObject = Kernel::System::File->new();

    my @Tasks = (
        {
            Module => 'PerlModules',
            Message => 'Check if required perl modules are installed',
        },
        {
            Module => 'DB',
            Message => 'Database installation started.',
        },
    );

    TASK:
    for my $Task (@Tasks) {

        print "\n    $Task->{Message}";

        # Create object.
        my $Loaded = $FileObject->Require(
            "Kernel/System/Installer/$Task->{Module}",
        );

        die if !$Loaded;
        
        my $ModuleObject = "Kernel::System::Installer::$Task->{Module}"->new();
        my $Result = $ModuleObject->Run();

        if (!$Result->{Success}) {
            print "\n\n    ERROR: Task $Task->{Module} - $Task->{Method} failed!";
            print "\n        $Result->{Message}\n\n";
            die;
        }

        if ($Result->{Message}) {
            print "\n    $Result->{Message}";
        }
    }

    print "\nInstallation finished.\n";
}


1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

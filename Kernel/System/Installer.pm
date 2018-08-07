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

    Print("\nInstallation started.");

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

        Print("\n    $Task->{Message}");

        # Create object.
        my $Loaded = $FileObject->Require(
            "Kernel/System/Installer/$Task->{Module}",
        );

        die if !$Loaded;
        
        my $ModuleObject = "Kernel::System::Installer::$Task->{Module}"->new();
        my $Result = $ModuleObject->Run();

        if (!$Result->{Success}) {
            Print("\n\n    ERROR: Task $Task->{Module} - $Task->{Method} failed!");
            Print("\n        $Result->{Message}\n\n");
            die;
        }

        if ($Result->{Message}) {
            Print("\n    $Result->{Message}");
        }
    }

    Print("\nInstallation finished.\n");
}

sub Print {
    my ($Text) = @_;

    print _ReplaceColorTags($Text);

    return;
}

sub _ReplaceColorTags {
    my ($Text) = @_;

    $Text //= '';

    $Text =~ s{<(green|yellow|red)>(.*?)</\1>}{_Color($1, $2)}gsmxe;

    return $Text;
}

sub _Color {
    my ( $Color, $Text ) = @_;

    return Term::ANSIColor::color($Color) . $Text . Term::ANSIColor::color('reset');
}


1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

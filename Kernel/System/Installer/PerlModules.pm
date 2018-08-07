# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Installer::PerlModules;    ## no critic

use strict;
use warnings;

use Kernel::System::Environment;
use Kernel::System::VariableCheck qw( :all );

=head1 NAME

Kernel::System::Installer::PerlModules - Environment check for required Perl modules.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the ObjectManager, use it directly instead:

    use Kernel::System::Installer::PerlModules;
    my $PerlModulesObject = Kernel::System::Installer::PerlModules->new();
    $PerlModulesObject->Run();

The ObjectManager should not be used especially when using this module from a script,
because we want this to always work, no matter if any dependencies fail.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    $Self->{Options} = $Param{Options} // {};

    $Self->{InstTypeToCMD} = {

        # [InstType] => {
        #    CMD       => '[cmd to install module]',
        #    UseModule => 1/0,
        # }
        # Set UseModule to 1 if you want to use the CPAN module name of the package as replace string:
        #   e.g. yum install "perl(Date::Format)"
        # If you set it 0 it will use the name for the InstType of the module:
        #   e.g. apt-get install -y libtimedate-perl
        # and as fallback the default cpan install command:
        #   e.g. cpan DBD::Oracle
        aptget => {
            CMD       => 'apt-get install -y %s',
            UseModule => 0,
        },
        emerge => {
            CMD       => 'emerge %s',
            UseModule => 0,
        },
        ppm => {
            CMD       => 'ppm install %s',
            UseModule => 0,
        },
        yum => {
            CMD       => 'yum install "%s"',
            SubCMD    => 'perl(%s)',
            UseModule => 0,
        },
        zypper => {
            CMD       => 'zypper install %s',
            UseModule => 0,
        },
        ports => {
            CMD       => 'cd /usr/ports %s',
            SubCMD    => '&& make -C %s install clean',
            UseModule => 0,
        },
        default => {
            CMD => 'cpan %s',
        },
    };

    $Self->{DistToInstType} = {

        # apt-get
        debian => 'aptget',
        ubuntu => 'aptget',

        # emerge
        #   For reasons unknown, some environments return "gentoo" (incl. the quotes).
        '"gentoo"' => 'emerge',
        gentoo     => 'emerge',

        # yum
        centos => 'yum',
        fedora => 'yum',
        rhel   => 'yum',
        redhat => 'yum',

        # zypper
        suse => 'zypper',

        # FreeBSD
        freebsd => 'ports',
    };

    eval {
        require Linux::Distribution;    ## nofilter(TidyAll::Plugin::OTRS::Perl::Require)
        import Linux::Distribution;
        $Self->{OSDist} = Linux::Distribution::distribution_name() || '';
    };
    if ( !defined $Self->{OSDist} ) {
        $Self->{OSDist} = $^O;
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my @NeededModules = (
        {
            Module    => 'DBI',
            Required  => 1,
            InstTypes => {
                aptget => 'libdbi-perl',
                emerge => 'dev-perl/DBI',
                zypper => 'perl-DBI',
                ports  => 'databases/p5-DBI',
            },
        },
    );

    my $Message;
    my $Error;

    if ( $Self->{Options}->{PackageList} ) {

        my %PackagesByCommand = $Self->_PackageList( \@NeededModules );

        if ( IsHashRefWithData( \%PackagesByCommand ) ) {

            for my $CMD ( sort keys %PackagesByCommand ) {

                # Wrap the package name in the the sub command
                if ( $PackagesByCommand{$CMD}->{SubCMD} ) {
                    for my $Package ( @{ $PackagesByCommand{$CMD}->{Packages} } ) {
                        $Package = sprintf $PackagesByCommand{$CMD}->{SubCMD}, $Package;
                    }
                }

                my $CMDText = sprintf $CMD, join ' ', @{ $PackagesByCommand{$CMD}->{Packages} };

                $Message .= "$CMDText\n\n";
            }
        }
    }
    else {
        my $Depends = 0;

        # Try to determine module version number.
        for my $Module (@NeededModules) {
            my $Check = $Self->_Check( $Module, $Depends );
            if ( !$Check->{Success} ) {
                $Error = 1;
            }
            $Message .= $Check->{Message};
        }

        if ( $Self->{Options}->{AllModules} ) {
            $Message .= "\nBundled modules:\n\n";

            my %PerlInfo = Kernel::System::Environment->PerlInfoGet(
                BundledModules => 1,
            );

            for my $Module ( sort keys %{ $PerlInfo{Modules} } ) {
                my $Check = $Self->_Check(
                    {
                        Module   => $Module,
                        Required => 1,
                    },
                    $Depends,
                );
                if ( !$Check->{Success} ) {
                    $Error = 1;
                }
                $Message .= $Check->{Message};
            }
        }
    }

    return {
        Success => $Error ? 0 : 1,
        Message => $Message,
    };
}

sub _Check {
    my ( $Self, $Module, $Depends ) = @_;

    my $Message = "  " x ( $Depends + 1 );
    $Message .= "o $Module->{Module}";
    my $Length = 33 - ( length( $Module->{Module} ) + ( $Depends * 2 ) );
    $Message .= '.' x $Length;

    my $Error;

    my $Version = Kernel::System::Environment->ModuleVersionGet( Module => $Module->{Module} );
    if ($Version) {

        # cleanup version number
        my $CleanedVersion = $Self->_VersionClean(
            Version => $Version,
        );

        my $ErrorMessage;

        # Test if all module dependencies are installed by requiring the module.
        #   Don't do this for Net::DNS as it seems to take very long (>20s) in a
        #   mod_perl environment sometimes.
        my %DontRequire = (
            'Net::DNS'     => 1,
            'Email::Valid' => 1,    # uses Net::DNS internally
        );

        ## no critic
        if ( !$DontRequire{ $Module->{Module} } && !eval "require $Module->{Module}" ) {
            $ErrorMessage .= 'Not all prerequisites for this module correctly installed. ';
        }
        ## use critic

        if ( $Module->{NotSupported} ) {

            my $NotSupported = 0;
            ITEM:
            for my $Item ( @{ $Module->{NotSupported} } ) {

                # cleanup item version number
                my $ItemVersion = $Self->_VersionClean(
                    Version => $Item->{Version},
                );

                if ( $CleanedVersion == $ItemVersion ) {
                    $NotSupported = $Item->{Comment};
                    last ITEM;
                }
            }

            if ($NotSupported) {
                $ErrorMessage .= "Version $Version not supported! $NotSupported ";
            }
        }

        if ( $Module->{Version} ) {

            # cleanup item version number
            my $RequiredModuleVersion = $Self->_VersionClean(
                Version => $Module->{Version},
            );

            if ( $CleanedVersion < $RequiredModuleVersion ) {
                $ErrorMessage
                    .= "Version $Version installed but $Module->{Version} or higher is required! ";
            }
        }

        if ($ErrorMessage) {
            $Message .= "<red>$ErrorMessage</red>\n";
            $Error = 1;
        }
        else {
            my $OutputVersion = $Version;

            if ( $OutputVersion =~ m{ [0-9.] }xms ) {
                $OutputVersion = 'v' . $OutputVersion;
            }

            $Message .= "<green>ok</green> ($OutputVersion)\n";
        }
    }
    else {
        my $Comment  = $Module->{Comment} ? ' - ' . $Module->{Comment} : '';
        my $Required = $Module->{Required};
        my $Color    = 'yellow';

        # OS Install Command
        my %InstallCommand = $Self->_GetInstallCommand($Module);

        # create example installation string for module
        my $InstallText = '';
        if ( IsHashRefWithData( \%InstallCommand ) ) {
            my $CMD = $InstallCommand{CMD};
            if ( $InstallCommand{SubCMD} ) {
                $CMD = sprintf $InstallCommand{CMD}, $InstallCommand{SubCMD};
            }

            $InstallText = " Use: '" . sprintf( $CMD, $InstallCommand{Package} ) . "'";
        }

        if ($Required) {
            $Required = 'required';
            $Color    = 'red';
            $Error    = 1;
        }
        else {
            $Required = 'optional';
        }
        $Message .= "<$Color>Not installed!</$Color> $InstallText ($Required$Comment)\n";
    }

    if ( $Module->{Depends} ) {
        for my $ModuleSub ( @{ $Module->{Depends} } ) {
            my $DependencyCheck = $Self->_Check( $ModuleSub, $Depends + 1 );
            if ( !$DependencyCheck->{Success} ) {
                $Error = 1;
            }
            $Message .= $DependencyCheck->{Message};
        }
    }

    return {
        Success => $Error ? 0 : 1,
        Message => $Message,
    };
}

=head2 _PackageList()

Returns a hash with commands and a list of packages which can be installed with each command.

    my %PackagesByCommand = $PerlModulesObject->_PackageList(
        [
            {
                Module    => 'Archive::Tar',
                Required  => 1,
                Comment   => 'Required for compressed file generation (in perlcore).',
                InstTypes => {
                    emerge => 'perl-core/Archive-Tar',
                    zypper => 'perl-Archive-Tar',
                    ports  => 'archivers/p5-Archive-Tar',
                },
            },
            {
                Module    => 'Archive::Zip',
                Required  => 1,
                Comment   => 'Required for compressed file generation.',
                InstTypes => {
                    aptget => 'libarchive-zip-perl',
                    emerge => 'dev-perl/Archive-Zip',
                    zypper => 'perl-Archive-Zip',
                    ports  => 'archivers/p5-Archive-Zip',
                },
            },
            ...
        ],
    );

    Returns:

        my %PackagesByCommand = (
            'apt-get install -y' => {
                SubCMD => 'perl(%s)',
                Packages => [
                    'libarchive-zip-perl',
                    'libtimedate-perl',
                    'libdatetime-perl',
                ],
            },
            'cpan %s' => {
                Packages => [
                    'CryptX',
                    'Specio',
                    'Specio::Subs',
                ],
            },
        );

=cut

sub _PackageList {
    my ( $Self, $PackageList ) = @_;

    my %PackagesByCommand;

    MODULE:
    for my $Module ( @{$PackageList} ) {

        next MODULE if !$Module->{Required};

        my $Version = Kernel::System::Environment->ModuleVersionGet( Module => $Module->{Module} );

        next MODULE if $Version;

        my %InstallCommand = $Self->_GetInstallCommand($Module);

        if ( $Module->{Depends} ) {

            MODULESUB:
            for my $ModuleSub ( @{ $Module->{Depends} } ) {
                next MODULESUB if !$ModuleSub->{Required};

                my %InstallCommandSub = $Self->_GetInstallCommand($ModuleSub);
                next MODULESUB if !IsHashRefWithData( \%InstallCommandSub );

                push @{ $PackagesByCommand{ $InstallCommandSub{CMD} }->{Packages} }, $InstallCommandSub{Package};

                next MODULESUB if !$InstallCommandSub{SubCMD};
                $PackagesByCommand{ $InstallCommandSub{CMD} }->{SubCMD} = $InstallCommandSub{SubCMD};
            }
        }

        next MODULE if !IsHashRefWithData( \%InstallCommand );

        push @{ $PackagesByCommand{ $InstallCommand{CMD} }->{Packages} }, $InstallCommand{Package};

        next MODULE if !$InstallCommand{SubCMD};
        $PackagesByCommand{ $InstallCommand{CMD} }->{SubCMD} = $InstallCommand{SubCMD};
    }

    return %PackagesByCommand;
}

sub _GetInstallCommand {
    my ( $Self, $Module ) = @_;

    my $CMD;
    my $SubCMD;
    my $Package;

    # returns the installation type e.g. ppm
    my $InstType      = $Self->{DistToInstType}->{ $Self->{OSDist} };
    my $OutputInstall = 1;

    if ($InstType) {

        # gets the install command for installation type
        # e.g. ppm install %s
        # default is the cpan install command
        # e.g. cpan %s
        $CMD    = $Self->{InstTypeToCMD}->{$InstType}->{CMD};
        $SubCMD = $Self->{InstTypeToCMD}->{$InstType}->{SubCMD};

        # gets the target package
        if (
            exists $Module->{InstTypes}->{$InstType}
            && !defined $Module->{InstTypes}->{$InstType}
            )
        {
            # if we a hash key for the installation type but a undefined value
            # then we prevent the output for the installation command
            $OutputInstall = 0;
        }
        elsif ( $Self->{InstTypeToCMD}->{$InstType}->{UseModule} ) {

            # default is the cpan module name
            $Package = $Module->{Module};
        }
        else {
            # if the package name is defined for the installation type
            # e.g. ppm then we use this as package name
            $Package = $Module->{InstTypes}->{$InstType};
        }
    }

    return if !$OutputInstall;

    if ( !$CMD || !$Package ) {
        $CMD     = $Self->{InstTypeToCMD}->{default}->{CMD};
        $SubCMD  = $Self->{InstTypeToCMD}->{default}->{SubCMD};
        $Package = $Module->{Module};
    }

    return (
        CMD     => $CMD,
        SubCMD  => $SubCMD,
        Package => $Package,
    );
}

sub _VersionClean {
    my ( $Self, %Param ) = @_;

    return 0 if !$Param{Version};
    return 0 if $Param{Version} eq 'undef';

    # Replace all special characters with a dot.
    $Param{Version} =~ s{ [_-] }{.}xmsg;

    my @VersionParts = split q{\.}, $Param{Version};

    my $CleanedVersion = '';
    for my $Count ( 0 .. 4 ) {
        $VersionParts[$Count] ||= 0;
        $CleanedVersion .= sprintf "%04d", $VersionParts[$Count];
    }

    return int $CleanedVersion;
}

1;

# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::XML;

use strict;
use warnings;

use Kernel::System::Encode;
use Digest::MD5;

sub new {
    my ( $Type, %Param ) = @_;

    # Allocate new hash for object.
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}


=head2 XMLParse()

parse an XML file

    my @XMLStructure = $XMLObject->XMLParse( String => $FileString );

    my @XMLStructure = $XMLObject->XMLParse( String => \$FileStringScalar );

=cut

sub XMLParse {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !defined $Param{String} ) {
        # TODO: Log.
        print "Missing String.\n";

        return;
    }

    # check input type
    if ( ref $Param{String} ) {
        $Param{String} = ${ $Param{String} };
    }

    # get encode object
    my $EncodeObject = Kernel::System::Encode->new();

    # create checksum
    my $CookedString = $Param{String};
    $EncodeObject->EncodeOutput( \$CookedString );
    my $MD5Object = Digest::MD5->new();
    $MD5Object->add($CookedString);

    # cleanup global vars
    undef $Self->{XMLARRAY};
    $Self->{XMLLevel}    = 0;
    $Self->{XMLTagCount} = 0;
    undef $Self->{XMLLevelTag};
    undef $Self->{XMLLevelCount};

    # convert string
    if ( $Param{String} =~ /(<.+?>)/ ) {
        if ( $1 !~ /(utf-8|utf8)/i && $1 =~ /encoding=('|")(.+?)('|")/i ) {
            my $SourceCharset = $2;
            $Param{String} =~ s/$SourceCharset/utf-8/i;
            $Param{String} = $EncodeObject->Convert(
                Text  => $Param{String},
                From  => $SourceCharset,
                To    => 'utf-8',
                Force => 1,
            );
        }
    }

    # load parse package and parse
    my $UseFallback = 1;

    if ( eval 'require XML::Parser' ) {    ## no critic
        my $Parser = XML::Parser->new(
            Handlers => {
                Start => sub { $Self->_HS(@_); },
                End   => sub { $Self->_ES(@_); },
                Char  => sub { $Self->_CS(@_); },
            },
        );

        # get sourcename now to avoid a possible race condition where
        # $@ could get altered after a failing eval!
        my $Sourcename = $Param{Sourcename} ? "\n\n($Param{Sourcename})" : '';

        if ( eval { $Parser->parse( $Param{String} ) } ) {
            $UseFallback = 0;

            # remember, XML::Parser is managing e. g. &amp; by it self
            $Self->{XMLQuote} = 0;
        }
        else {
            # TODO Log error.
        }
    }

    if ($UseFallback) {
        require XML::Parser::Lite;    ## no critic

        my $Parser = XML::Parser::Lite->new(
            Handlers => {
                Start => sub { $Self->_HS(@_); },
                End   => sub { $Self->_ES(@_); },
                Char  => sub { $Self->_CS(@_); },
            },
        );
        $Parser->parse( $Param{String} );

        # remember, XML::Parser::Lite is managing e. g. &amp; NOT by it self
        $Self->{XMLQuote} = 1;
    }

    # quote
    for my $XMLElement ( @{ $Self->{XMLARRAY} } ) {
        $Self->_Decode($XMLElement);
    }

    return @{ $Self->{XMLARRAY} };
}

sub _Decode {
    my ( $Self, $A ) = @_;

    # get encode object
    my $EncodeObject = Kernel::System::Encode->new();

    for ( sort keys %{$A} ) {
        if ( ref $A->{$_} eq 'ARRAY' ) {
            for my $B ( @{ $A->{$_} } ) {
                $Self->_Decode($B);
            }
        }

        # decode
        elsif ( defined $A->{$_} ) {

            # check if decode is already done by parser
            if ( $Self->{XMLQuote} ) {
                my %Map = (
                    'amp'  => '&',
                    'lt'   => '<',
                    'gt'   => '>',
                    'quot' => '"',
                );
                $A->{$_} =~ s/&(amp|lt|gt|quot);/$Map{$1}/g;
            }

            # convert into default charset
            $A->{$_} = $EncodeObject->Convert(
                Text  => $A->{$_},
                From  => 'utf-8',
                To    => 'utf-8',
                Force => 1,
            );
        }
    }

    return 1;
}

sub _HS {
    my ( $Self, $Expat, $Element, %Attr ) = @_;

    if ( $Self->{LastTag} ) {
        push @{ $Self->{XMLARRAY} }, { %{ $Self->{LastTag} }, Content => $Self->{C} };
    }

    undef $Self->{LastTag};
    undef $Self->{C};

    $Self->{XMLLevel}++;
    $Self->{XMLTagCount}++;
    $Self->{XMLLevelTag}->{ $Self->{XMLLevel} } = $Element;

    if ( $Self->{Tll} && $Self->{Tll} > $Self->{XMLLevel} ) {
        for ( ( $Self->{XMLLevel} + 1 ) .. 30 ) {
            undef $Self->{XMLLevelCount}->{$_};
        }
    }

    $Self->{XMLLevelCount}->{ $Self->{XMLLevel} }->{$Element}++;

    # remember old level
    $Self->{Tll} = $Self->{XMLLevel};

    my $Key = '';
    for ( 1 .. ( $Self->{XMLLevel} ) ) {
        $Key .= "{'$Self->{XMLLevelTag}->{$_}'}";
        $Key .= "[" . $Self->{XMLLevelCount}->{$_}->{ $Self->{XMLLevelTag}->{$_} } . "]";
    }

    $Self->{LastTag} = {
        %Attr,
        TagType      => 'Start',
        Tag          => $Element,
        TagLevel     => $Self->{XMLLevel},
        TagCount     => $Self->{XMLTagCount},
        TagLastLevel => $Self->{XMLLevelTag}->{ ( $Self->{XMLLevel} - 1 ) },
    };

    return 1;
}

sub _CS {
    my ( $Self, $Expat, $Element, $I, $II ) = @_;

    if ( $Self->{LastTag} ) {
        $Self->{C} .= $Element;
    }

    return 1;
}

sub _ES {
    my ( $Self, $Expat, $Element ) = @_;

    $Self->{XMLTagCount}++;

    if ( $Self->{LastTag} ) {
        push @{ $Self->{XMLARRAY} }, { %{ $Self->{LastTag} }, Content => $Self->{C} };
    }

    undef $Self->{LastTag};
    undef $Self->{C};

    push(
        @{ $Self->{XMLARRAY} },
        {
            TagType  => 'End',
            TagLevel => $Self->{XMLLevel},
            TagCount => $Self->{XMLTagCount},
            Tag      => $Element
        },
    );

    $Self->{XMLLevel} = $Self->{XMLLevel} - 1;

    return 1;
}


1;
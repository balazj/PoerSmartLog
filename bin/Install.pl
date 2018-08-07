#!/usr/bin/perl
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
# --

use strict;
use warnings;

# use ../../ as lib location
use FindBin qw($Bin);
use lib "$Bin/..";
use lib "$Bin/../Kernel/cpan-lib";

use Kernel::System::Installer;

my $InstallerObject = Kernel::System::Installer->new();

$InstallerObject->Install();
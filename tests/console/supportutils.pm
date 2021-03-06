# SUSE's openQA tests
#
# Copyright © 2019-2020 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Test is files created by supportconfig are readable and contain some basic data.
# - Delete any previously existing supportconfig data
# - Run supportconfig -t . -B test
# - Check for supportconfig contents
# - Cleanup supportconfig data
# Maintainer: Juraj Hura <jhura@suse.com>

use base "consoletest";
use strict;
use warnings;
use testapi;

sub run {
    my $self = shift;
    $self->select_serial_terminal;

    assert_script_run "rm -rf nts_* scc_* ||:";
    assert_script_run "supportconfig -t . -B test", 800;

    # bcc#1166774
    if (script_run("test -d scc_test") == 0) {
        assert_script_run "cd scc_test";
    } else {
        assert_script_run "cd nts_test";
    }

    # Check few file whether expected content is there.
    assert_script_run "diff <(awk '/\\/proc\\/cmdline/{getline; print}' boot.txt) /proc/cmdline";
    assert_script_run "grep -q -f /etc/os-release basic-environment.txt";

    assert_script_run "cd ..";
    assert_script_run "rm -rf nts_* scc_* ||:";
}

1;

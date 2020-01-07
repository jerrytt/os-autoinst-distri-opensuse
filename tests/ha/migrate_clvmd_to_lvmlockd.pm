# SUSE's openQA tests
#
# Copyright (c) 2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Workarounds after upgrade from cluster with clvmd into lvmlockd only systems
# Maintainer: Alvaro Carvajal <acarvajal@suse.com>

use base 'opensusebasetest';
use strict;
use warnings;
use utils qw(zypper_call systemctl zypper_enable_install_dvd);
use testapi;
use lockapi;
use hacluster;

sub run {
    my ($self)       = @_;
    my $cluster_name = get_cluster_name;
    my $lvm_conf     = '/etc/lvm/lvm.conf';

    # We may execute this test after a reboot, so we need to log in
    select_console 'root-console';

    # Only perform clvm to lvmlockd migration if the cluster has clvm resources
    my $clvm_rsc = script_run "$crm_mon_cmd | grep -wq clvm";
    return unless (defined $clvm_rsc and $clvm_rsc == 0);

    barrier_wait("CLVM_TO_LVMLOCKD_START_$cluster_name");
    my $ret = zypper_call('in lvm2-lockd', exitcode => [0, 104]);

    if ($ret == 104) {
        # Workaround for offline migrations
        zypper_enable_install_dvd;
        zypper_call 'in lvm2-lockd';
    }

    if (is_node(1)) {
        # Stop all affected resources, and remove clvm resource from cluster
        for my $rsc (qw(fs_cluster_md vg_cluster_md cluster_md clvm)) {
            assert_script_run "crm resource stop $rsc";
        }
        assert_script_run 'crm configure delete clvm';

        # With clvm resource removed from the cluster, configure lvmlockd
        # Set use_lvmetad=1, lvmlockd supports lvmetad. Set locking_type=1 for lvmlockd. Enable lvmlockd
        set_lvm_config($lvm_conf, use_lvmetad => 1, locking_type => 1, use_lvmlockd => 1);

        # Sync files with other nodes
        exec_csync;

        # Add lvmlockd resource to cluster
        add_lock_mgr('lvmlockd');
        save_state;

        # Restart cluster_md
        assert_script_run 'crm resource start cluster_md';
        sleep 5;

        # Migrate volume group to lvmlockd
        assert_script_run 'vgchange --lock-type none --lock-opt force -y vg_cluster_md';
        assert_script_run 'vgchange --lock-type dlm vg_cluster_md';

        # Start volume group and filesystem resources
        assert_script_run 'crm resource start vg_cluster_md';
        assert_script_run 'crm resource start fs_cluster_md';
        sleep 5;
        save_state;
    }

    # Screenshot before cleaning the screen
    save_screenshot;

    # Reset the console on all nodes, as the next test will re-select them
    $self->clear_and_verify_console;

    # Wait for all nodes to finish
    barrier_wait("CLVM_TO_LVMLOCKD_DONE_$cluster_name");
}

1;
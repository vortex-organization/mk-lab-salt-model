#    Copyright 2013 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

from __future__ import division
from __future__ import unicode_literals

import re

from devops.helpers.helpers import wait
from proboscis.asserts import assert_equal
from proboscis.asserts import assert_true
from proboscis import test

from fuelweb_test.helpers.decorators import log_snapshot_after_test
from fuelweb_test.helpers.eb_tables import Ebtables
from fuelweb_test.helpers import os_actions
from fuelweb_test.settings import DEPLOYMENT_MODE
from fuelweb_test.settings import MIRROR_UBUNTU
from fuelweb_test.settings import NODE_VOLUME_SIZE
from fuelweb_test.settings import NEUTRON_SEGMENT
from fuelweb_test.settings import NEUTRON_SEGMENT_TYPE
from fuelweb_test.settings import iface_alias
from fuelweb_test.tests.base_test_case import SetupEnvironment
from fuelweb_test.tests.base_test_case import TestBasic
from fuelweb_test import logger
from fuelweb_test.tests.test_ha_one_controller_base\
    import HAOneControllerNeutronBase




@test(groups=["deploy_run_wally"])
class MultiroleComputeCinder(TestBasic):
    """Test Ceph Wally"""

    @test(depends_on=[SetupEnvironment.prepare_slaves_3], 
	      depends_on_groups=["deploy_master_custom"],
          groups=["deploy_run_wally"])
    @log_snapshot_after_test
    def deploy_run_wally(self):
        """Deploy cluster with Ceph compute

        Scenario:
            1. Create cluster with Ceph
            2. Add 1 node with controller role
            3. Add 2 node with compute roles
			4. Add 5 node with ceph-osd roles
			5. Config ceph_journal on SSD disks
            6. Deploy the cluster
            5. Run Wally tests
            6. Collect and send report to Testrail

        Duration ~330 m

        """
		self.check_run("empty_ifup")
        self.show_step(1)
        self.env.revert_snapshot("ready_with_8_slaves")

        cluster_id = self.fuel_web.create_cluster(
            name=self.__class__.__name__,
            mode=DEPLOYMENT_MODE,
        )
        self.fuel_web.update_nodes(
            cluster_id,
            {
                'slave-01': ['controller'],
                'slave-02': ['compute'],
                'slave-03': ['compute'],
				'slave-04': ['ceph-osd'],
				'slave-05': ['ceph-osd'],
				'slave-06': ['ceph-osd'],
				'slave-07': ['ceph-osd'],
				'slave-08': ['ceph-osd']
            }
        )
        self.fuel_web.deploy_cluster_wait(cluster_id)

        self.env.make_snapshot("deploy_run_wally",
                               is_make=True)

import pytest
import os

from fuelweb_test import settings
from fuelweb_test.helpers.shaker import ShakerEngine
from fuelweb_test.settings import NEUTRON_SEGMENT
from fuelweb_test.settings import iface_alias
from fuelweb_test import logger
from copy import deepcopy

from fuelweb_test.testrail.performance_testrail_report import ShakerTestResultReporter


@pytest.mark.need_ready_master
class TestPerfBonding(object):

    BOND_CONFIG = [
        {
            'mode': '802.3ad',
            'name': 'bond0',
            'slaves': [
                {'name': iface_alias('eth2')},
                {'name': iface_alias('eth3')}
            ],
            'type': 'bond',
            'assigned_networks': [],
            'bond_properties': {'lacp_rate': 'slow', 'type__': 'linux', 'mode': '802.3ad', 'xmit_hash_policy': 'layer3+4'},
            'interface_properties': {'dpdk': {'available': True, 'enabled': False}, 'disable_offloading': True, 'mtu': None},
            'offloading_modes': [{'state': True, 'name': 'l2-fwd-offload', 'sub': []}, {'state': True, 'name': 'rx-all', 'sub': []}, {'state': True, 'name': 'tx-nocache-copy', 'sub': []}, {'state': True, 'name': 'rx-vlan-filter', 'sub': []}, {'state': True, 'name': 'receive-hashing', 'sub': []}, {'state': True, 'name': 'ntuple-filters', 'sub': []}, {'state': True, 'name': 'tx-vlan-offload', 'sub': []}, {'state': True, 'name': 'rx-vlan-offload', 'sub': []}, {'state': True, 'name': 'large-receive-offload', 'sub': []}, {'state': True, 'name': 'generic-receive-offload', 'sub': []}, {'state': True, 'name': 'generic-segmentation-offload', 'sub': []}, {'state': True, 'name': 'tcp-segmentation-offload', 'sub': [{'state': True, 'name': 'tx-tcp6-segmentation', 'sub': []}, {'state': True, 'name': 'tx-tcp-segmentation', 'sub': []}]}, {'state': True, 'name': 'scatter-gather', 'sub': [{'state': True, 'name': 'tx-scatter-gather', 'sub': []}]}, {'state': True, 'name': 'tx-checksumming', 'sub': [{'state': True, 'name': 'tx-checksum-sctp', 'sub': []}, {'state': True, 'name': 'tx-checksum-ipv6', 'sub': []}, {'state': True, 'name': 'tx-checksum-ipv4', 'sub': []}]}, {'state': True, 'name': 'rx-checksumming', 'sub': []}]
        }
    ]

    INTERFACES = {
        'eno1': ['public', 'fuelweb_admin'],
        'bond0': ['storage', 'management', 'private']
    }

    def deploy_env(self, segmentation, dvr, l3ha, offloading):
        assert segmentation == "vlan" or segmentation == "vxlan"
        if dvr:
            assert not l3ha
        if l3ha:
            assert not dvr

        bond_config = deepcopy(TestPerfBonding.BOND_CONFIG)
        for mode in bond_config[0]["offloading_modes"]:
            mode["state"] = offloading

        cluster_settings = {
            "sahara": self.manager.env_settings['components'].get('sahara', False),
            "ceilometer": self.manager.env_settings['components'].get('ceilometer', False),
            "ironic": self.manager.env_settings['components'].get('ironic', False),
            "user": self.manager.env_config.get("user", "admin"),
            "password": self.manager.env_config.get("password", "admin"),
            "tenant": self.manager.env_config.get("tenant", "admin"),
            "volumes_lvm": self.manager.env_settings['storages'].get("volume-lvm", False),
            "volumes_ceph": self.manager.env_settings['storages'].get("volume-ceph", False),
            "images_ceph": self.manager.env_settings['storages'].get("image-ceph", False),
            "ephemeral_ceph": self.manager.env_settings['storages'].get("ephemeral-ceph", False),
            "objects_ceph": self.manager.env_settings['storages'].get("rados-ceph", False),
            "osd_pool_size": str(self.manager.env_settings['storages'].get("replica-ceph", 2)),
            "net_provider": self.manager.env_config['network'].get('provider', 'neutron'),
            "net_segment_type": segmentation,
            "assign_to_all_nodes": self.manager.env_config['network'].get('pubip-to-all', False),
            "neutron_l3_ha": l3ha,
            "neutron_dvr": dvr,
            "neutron_l2_pop": self.manager.env_config['network'].get('neutron-l2-pop', False)
        }

        cluster_name = self.manager.env_config['name']
        snapshot_name = "ready_cluster_{}".format(cluster_name)
        #self.env.revert_snapshot(snapshot_name)

        nof_slaves = int(self.manager.full_config['template']['slaves'])
        #self.env.revert_snapshot("ready_with_{}_slaves".format(nof_slaves))
        #self.env.revert_snapshot("ready")
        assert self.manager.get_ready_slaves(nof_slaves)

        cluster_id = self.manager.fuel_web.create_cluster(
            name=self.manager.env_config['name'],
            mode=settings.DEPLOYMENT_MODE,
            release_name=self.manager.env_config['release'],
            settings=cluster_settings)

        self.assigned_slaves = set()
        self.manager._context._storage['cluster_id'] = cluster_id
        logger.info("Add nodes to env {}".format(cluster_id))
        names = "slave-{:02}"
        num = iter(xrange(1, nof_slaves + 1))
        nodes = {}
        for new in self.manager.env_config['nodes']:
            for _ in xrange(new['count']):
                name = names.format(next(num))
                while name in self.assigned_slaves:
                    name = names.format(next(num))

                self.assigned_slaves.add(name)
                nodes[name] = new['roles']
                logger.info("Set roles {} to node {}".format(new['roles'], name))

        self.manager.fuel_web.update_nodes(cluster_id, nodes)

        nailgun_nodes = self.manager.fuel_web.client.list_cluster_nodes(cluster_id)
        for node in nailgun_nodes:
            self.manager.fuel_web.update_node_networks(
                node['id'], interfaces_dict=deepcopy(TestPerfBonding.INTERFACES),
                raw_data=bond_config
            )
        self.manager.fuel_web.deploy_cluster_wait(cluster_id)
        self.manager.env.make_snapshot(snapshot_name, is_make=True)
        self.manager.env.resume_environment()

    @pytest.mark.perf_bonding
    def test_perf_bonding(self):
        """OLOLO!

        Scenario:
            1. Ololo

        Duration ololoshechka
        Snapshot mr. ololoshka
        """

        # self.BOND_CONFIG = [
        #     {
        #         'mode': '802.3ad',
        #         'name': 'bond0',
        #         'slaves': [
        #             {'name': iface_alias('eth2')},
        #             {'name': iface_alias('eth3')}
        #         ],
        #         'type': 'bond',
        #         'assigned_networks': [],
        #         'bond_properties': {'lacp_rate': 'slow', 'type__': 'linux', 'mode': '802.3ad', 'xmit_hash_policy': 'layer3+4'},
        #         'interface_properties': {'dpdk': {'available': True, 'enabled': False}, 'disable_offloading': True, 'mtu': None},
        #         'offloading_modes': [{'state': True, 'name': 'l2-fwd-offload', 'sub': []}, {'state': True, 'name': 'rx-all', 'sub': []}, {'state': True, 'name': 'tx-nocache-copy', 'sub': []}, {'state': True, 'name': 'rx-vlan-filter', 'sub': []}, {'state': True, 'name': 'receive-hashing', 'sub': []}, {'state': True, 'name': 'ntuple-filters', 'sub': []}, {'state': True, 'name': 'tx-vlan-offload', 'sub': []}, {'state': True, 'name': 'rx-vlan-offload', 'sub': []}, {'state': True, 'name': 'large-receive-offload', 'sub': []}, {'state': True, 'name': 'generic-receive-offload', 'sub': []}, {'state': True, 'name': 'generic-segmentation-offload', 'sub': []}, {'state': True, 'name': 'tcp-segmentation-offload', 'sub': [{'state': True, 'name': 'tx-tcp6-segmentation', 'sub': []}, {'state': True, 'name': 'tx-tcp-segmentation', 'sub': []}]}, {'state': True, 'name': 'scatter-gather', 'sub': [{'state': True, 'name': 'tx-scatter-gather', 'sub': []}]}, {'state': True, 'name': 'tx-checksumming', 'sub': [{'state': True, 'name': 'tx-checksum-sctp', 'sub': []}, {'state': True, 'name': 'tx-checksum-ipv6', 'sub': []}, {'state': True, 'name': 'tx-checksum-ipv4', 'sub': []}]}, {'state': True, 'name': 'rx-checksumming', 'sub': []}]
        #     }
        # ]
        #
        # self.INTERFACES = {
        #     'eno1': [
        #         'public',
        #         'fuelweb_admin'
        #     ],
        #     'bond0': ['storage', 'management', 'private']
        # }
        #
        #
        # self.full_config = self.manager.full_config
        # slaves = int(self.full_config['template']['slaves'])
        # if not self.manager.get_ready_slaves(slaves):
        #     raise Exception("Not ready slaves")
        #
        # self.env_config = self.manager.env_config
        # self.env_settings = self.manager.env_settings
        # self._context = self.manager._context
        # self.fuel_web = self.manager.fuel_web
        # self.assigned_slaves = set()
        #
        # cluster_name = self.env_config['name']
        # snapshot_name = "ready_cluster_{}".format(cluster_name)
        #
        # logger.info("Create env {}".format(
        #     self.env_config['name']))
        #
        # cluster_settings = {
        #     "sahara": self.manager.env_settings['components'].get('sahara', False),
        #     "ceilometer": self.manager.env_settings['components'].get('ceilometer', False),
        #     "ironic": self.manager.env_settings['components'].get('ironic', False),
        #     "user": self.manager.env_config.get("user", "admin"),
        #     "password": self.manager.env_config.get("password", "admin"),
        #     "tenant": self.manager.env_config.get("tenant", "admin"),
        #     "volumes_lvm": self.manager.env_settings['storages'].get("volume-lvm", False),
        #     "volumes_ceph": self.manager.env_settings['storages'].get("volume-ceph", False),
        #     "images_ceph": self.manager.env_settings['storages'].get("image-ceph", False),
        #     "ephemeral_ceph": self.manager.env_settings['storages'].get("ephemeral-ceph", False),
        #     "objects_ceph": self.manager.env_settings['storages'].get("rados-ceph", False),
        #     "osd_pool_size": str(self.manager.env_settings['storages'].get("replica-ceph", 2)),
        #     "net_provider": self.manager.env_config['network'].get('provider', 'neutron'),
        #     "net_segment_type": self.manager.env_config['network'].get('segment-type', 'vlan'),
        #     "assign_to_all_nodes": self.manager.env_config['network'].get('pubip-to-all', False),
        #     "neutron_l3_ha": self.manager.env_config['network'].get('neutron-l3-ha', False),
        #     "neutron_dvr": self.manager.env_config['network'].get('neutron-dvr', False),
        #     "neutron_l2_pop": self.manager.env_config['network'].get('neutron-l2-pop', False)
        # }
        #
        # cluster_id = self.fuel_web.create_cluster(
        #     name=self.env_config['name'],
        #     mode=settings.DEPLOYMENT_MODE,
        #     release_name=self.env_config['release'],
        #     settings=cluster_settings)
        #
        # self._context._storage['cluster_id'] = cluster_id
        # logger.info("Add nodes to env {}".format(cluster_id))
        # names = "slave-{:02}"
        # num = iter(xrange(1, slaves + 1))
        # nodes = {}
        # for new in self.env_config['nodes']:
        #     for _ in xrange(new['count']):
        #         name = names.format(next(num))
        #         while name in self.assigned_slaves:
        #             name = names.format(next(num))
        #
        #         self.assigned_slaves.add(name)
        #         nodes[name] = new['roles']
        #         logger.info("Set roles {} to node {}".format(
        #             new['roles'], name))
        #
        # self.fuel_web.update_nodes(cluster_id, nodes)
        #
        # nailgun_nodes = self.fuel_web.client.list_cluster_nodes(cluster_id)
        # for node in nailgun_nodes:
        #     logger.info("!!!!!!!!")
        #     logger.info(node)
        #     self.fuel_web.update_node_networks(
        #         node['id'], interfaces_dict=deepcopy(self.INTERFACES),
        #         raw_data=deepcopy(self.BOND_CONFIG)
        #     )
        # self.fuel_web.deploy_cluster_wait(cluster_id)
        # self.env.make_snapshot(snapshot_name, is_make=True)
        # self.env.resume_environment()

        # KEY = (segmentation vlan/tun, dvr on/off, l3ha on/off, tcp offloading on/off, target nodes/instances)
        # def deploy_env(self, segmentation, dvr, l3ha, offloading)

        test_results = {}
        path_to_run_shaker = os.environ.get('PATH_TO_RUN_SHAKER', 'faulty_path')

        self.deploy_env("vlan", True, False, True)

        admin_remote = self.manager.env.d_env.get_admin_remote()
        engine = ShakerEngine(admin_remote, path_to_run_shaker)
        data = engine.start_shaker_test()
        test_results[("vlan", True, False, True, "instances"): data]

        reporter = ShakerTestResultReporter(test_results)
        reporter.send_report()

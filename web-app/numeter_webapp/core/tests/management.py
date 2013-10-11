"""
Tests for commands.
"""

from django.test import LiveServerTestCase
from django.core.management import call_command
from core.models import User, Storage, Host
from core.tests.utils import storage_enabled, set_storage


class Manage_User_Test(LiveServerTestCase):

    def test_add_user(self):
        """Launch 'manage.py add-user --username=test --email=email --password=test --superuser'."""
        call_command('add-user', username='test', email='email', password='test', superuser=True, graphlib='dygraph-combined.js', database='default', verbosity=0)
        self.assertTrue(User.objects.all().exists(), 'No user created.')

    def test_delete_user(self):
        """Launch 'manage.py del-user --username=test -f'."""
        call_command('add-user', username='test', email='email', password='test', superuser=True, graphlib='dygraph-combined.js', database='default', verbosity=0)
        call_command('del-user', username='test', force=True, database='default', verbosity=0)
        self.assertFalse(User.objects.all().exists(), 'User exists ever.')


class Manage_Repair_Test(LiveServerTestCase):

    @set_storage(extras=['host'])
    def setUp(self):
        if Storage.objects.count() < 2:
            self.skipTest("Cannot do this test with less than 2 storages.")
        self.host = Host.objects.all()[0]

    def test_repair(self):
        """Launch 'manage.py repair_hosts -f'."""
        # Test cmd
        call_command('repair_hosts', force=True, database='default', verbosity=0)
        good_storage = self.host.storage
        bad_storage = Storage.objects.exclude(pk=good_storage.pk)[0]
        # Break and launch cmd
        self.host.storage = bad_storage
        self.host.save()
        call_command('repair_hosts', force=True, database='default', verbosity=0)
        self.host = Host.objects.get(pk=self.host.pk)
        self.assertEqual(self.host.storage, good_storage, "Broken host does not have been configurated.")

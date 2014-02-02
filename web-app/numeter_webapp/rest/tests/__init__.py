"""
rest tests module. Allow to launch a single TestCase or all.
"""

from login import Login_Test
from user import User_GET_list_Test, User_GET_detail_Test, User_POST_Test, User_DELETE_Test, User_PATCH_Test, User_POST_set_password_Test
from group import Group_GET_list_Test, Group_GET_detail_Test, Group_POST_Test, Group_DELETE_Test, Group_PATCH_Test
from storage import Storage_GET_list_Test, Storage_GET_detail_Test, Storage_POST_Test, Storage_DELETE_Test, Storage_PATCH_Test
from host import Host_GET_list_Test, Host_GET_detail_Test, Host_POST_Test, Host_DELETE_Test, Host_PATCH_Test, Host_POST_create_plugins_Test
from plugin import Plugin_GET_list_Test, Plugin_GET_detail_Test, Plugin_POST_Test, Plugin_DELETE_Test, Plugin_PATCH_Test, Plugin_POST_create_sources_Test
from source import Source_GET_list_Test, Source_GET_detail_Test, Source_POST_Test, Source_DELETE_Test, Source_PATCH_Test


def suite():
    import unittest
    TEST_CASES = (
        'rest.tests.login',
        'rest.tests.user',
        'rest.tests.group',
        'rest.tests.storage',
        'rest.tests.host',
        'rest.tests.plugin',
        'rest.tests.source',
    )
    suite = unittest.TestSuite()
    for t in TEST_CASES:
        suite.addTest(unittest.TestLoader().loadTestsFromModule(__import__(t, globals(), locals(), fromlist=["*"])))
    return suite
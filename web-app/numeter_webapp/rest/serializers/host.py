"""
Host Serializer module.
"""

from rest_framework import serializers
from core.models import Storage, Host


class HostSerializer(serializers.ModelSerializer):
    """Simple host serializer."""
    class Meta:
        model = Host


class HostUserSerializer(serializers.ModelSerializer):
    """Simple host serializer."""
    class Meta:
        model = Host
        fields = ('name', 'hostid',)


class HostCreationSerializer(serializers.ModelSerializer):
    """User's password serializer."""
    class Meta:
        model = Host
        fields = ('hostid',)

    def validate_hostid(self, attrs, source):
        value = attrs[source]
        self.storage = Storage.objects.which_storage(value)
        if not self.storage:
            raise serializers.ValidationError('No host with this ID found.')
        return attrs

    def save(self):
        return self.storage.create_host(self.init_data['hostid'])

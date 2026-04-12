from __future__ import annotations

import discord


def can_manage_schedule(interaction: discord.Interaction) -> bool:
    guild = interaction.guild
    if guild is None:
        return False

    user = interaction.user
    if user.id == guild.owner_id:
        return True

    interaction_permissions = getattr(interaction, "permissions", None)
    if isinstance(interaction_permissions, discord.Permissions):
        if interaction_permissions.administrator or interaction_permissions.manage_guild:
            return True

    member_permissions = getattr(user, "guild_permissions", None)
    if isinstance(member_permissions, discord.Permissions):
        if member_permissions.administrator or member_permissions.manage_guild:
            return True

    return False

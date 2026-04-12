from __future__ import annotations

import logging

from config import BotConfig
from discord_bot import MonitoringDiscordBot


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )


def main() -> None:
    configure_logging()
    try:
        config = BotConfig.from_env()
    except ValueError as exc:
        raise SystemExit(f"Configuration error: {exc}") from exc

    bot = MonitoringDiscordBot(config)
    bot.run(config.discord_bot_token)


if __name__ == "__main__":
    main()

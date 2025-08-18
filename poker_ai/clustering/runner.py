"""
Usage: poker_ai cluster [OPTIONS]

  Run clustering.

Options:
  --low_card_rank INTEGER        The starting hand rank from 2 through 14 for
                                 the deck we want to cluster. We recommend
                                 starting small.
  --high_card_rank INTEGER       The starting hand rank from 2 through 14 for
                                 the deck we want to cluster. We recommend
                                 starting small.
  --n_river_clusters INTEGER     The number of card information buckets we
                                 would like to create for the river. We
                                 recommend to start small.
  --n_turn_clusters INTEGER      The number of card information buckets we
                                 would like to create for the turn. We
                                 recommend to start small.
  --n_flop_clusters INTEGER      The number of card information buckets we
                                 would like to create for the flop. We
                                 recommend to start small.
  --n_simulations_river INTEGER  The number of opponent hand simulations we
                                 would like to run on the river. We recommend
                                 to start small.
  --n_simulations_turn INTEGER   The number of river card hand simulations we
                                 would like to run on the turn. We recommend
                                 to start small.
  --n_simulations_flop INTEGER   The number of turn card hand simulations we
                                 would like to run on the flop. We recommend
                                 to start small.
  --save_dir TEXT                Path to directory to save card info lookup
                                 table and betting stage centroids.
  --help                         Show this message and exit.
"""
import click

from poker_ai.clustering.unified_builder import UnifiedLUTBuilder


@click.command()
@click.option(
    "--low_card_rank",
    default=2,
    help=(
        "The starting hand rank from 2 through 14 for the deck. "
        "Default is 2 for full Texas Hold'em."
    )
)
@click.option(
    "--high_card_rank",
    default=14,
    help=(
        "The ending hand rank from 2 through 14 for the deck. "
        "Default is 14 (Ace) for full Texas Hold'em."
    )
)
@click.option(
    "--n_river_clusters",
    default=200,
    help=(
        "The number of card information buckets for the river. "
        "Default 200 for good strategy approximation."
    )
)
@click.option(
    "--n_turn_clusters",
    default=200,
    help=(
        "The number of card information buckets for the turn. "
        "Default 200 for good strategy approximation."
    )
)
@click.option(
    "--n_flop_clusters",
    default=200,
    help=(
        "The number of card information buckets for the flop. "
        "Default 200 for good strategy approximation."
    )
)
@click.option(
    "--n_simulations_river",
    default=10,
    help=(
        "The number of opponent hand simulations on the river. "
        "Default 10 for balanced speed/accuracy."
    )
)
@click.option(
    "--n_simulations_turn",
    default=10,
    help=(
        "The number of river card simulations on the turn. "
        "Default 10 for balanced speed/accuracy."
    )
)
@click.option(
    "--n_simulations_flop",
    default=10,
    help=(
        "The number of turn card simulations on the flop. "
        "Default 10 for balanced speed/accuracy."
    )
)
@click.option(
    "--save_dir",
    default="",
    help=(
        "Path to directory to save card info lookup table and betting stage "
        "centroids."
    )
)
@click.option(
    "--memory_limit_gb",
    default=50.0,
    help="Maximum memory usage in GB. Default 50GB."
)
@click.option(
    "--batch_size",
    default=50,
    help="Batch size for processing. Default 50."
)
@click.option(
    "--chunk_size",
    default=10,
    help="Chunk size for database flushing. Default 10."
)
def cluster(
    low_card_rank: int,
    high_card_rank: int,
    n_river_clusters: int,
    n_turn_clusters: int,
    n_flop_clusters: int,
    n_simulations_river: int,
    n_simulations_turn: int,
    n_simulations_flop: int,
    save_dir: str,
    memory_limit_gb: float,
    batch_size: int,
    chunk_size: int,
):
    """Run clustering with unified memory-safe builder."""
    with UnifiedLUTBuilder(
        n_simulations_river=n_simulations_river,
        n_simulations_turn=n_simulations_turn,
        n_simulations_flop=n_simulations_flop,
        low_card_rank=low_card_rank,
        high_card_rank=high_card_rank,
        n_river_clusters=n_river_clusters,
        n_turn_clusters=n_turn_clusters,
        n_flop_clusters=n_flop_clusters,
        memory_limit_gb=memory_limit_gb,
        batch_size=batch_size,
        chunk_size=chunk_size,
        save_dir=save_dir if save_dir else "."
    ) as builder:
        builder.compute()


if __name__ == "__main__":
    cluster()

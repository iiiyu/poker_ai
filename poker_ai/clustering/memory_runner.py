"""
Memory-efficient clustering runner with adaptive settings based on available RAM.
"""
import os
import psutil
import click
import logging

from poker_ai.clustering.memory_efficient_builder import MemoryEfficientLutBuilder

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
log = logging.getLogger("poker_ai.clustering.memory_runner")


def get_available_memory_gb():
    """Get available system memory in GB."""
    mem = psutil.virtual_memory()
    return mem.available / (1024**3)


def get_recommended_settings(available_gb: float, quality_mode: str = "auto"):
    """
    Get recommended settings based on available memory.
    
    Parameters
    ----------
    available_gb : float
        Available memory in GB
    quality_mode : str
        Quality mode: "low", "medium", "high", "ultra", or "auto"
    
    Returns
    -------
    dict
        Recommended settings
    """
    # Safety margin - use only 80% of available memory
    usable_gb = available_gb * 0.8
    
    if quality_mode == "auto":
        if usable_gb < 20:
            quality_mode = "low"
        elif usable_gb < 40:
            quality_mode = "medium"
        elif usable_gb < 60:
            quality_mode = "high"
        else:
            quality_mode = "ultra"
    
    settings = {
        "low": {
            "n_river_clusters": 100,
            "n_turn_clusters": 100,
            "n_flop_clusters": 100,
            "n_simulations_river": 5,
            "n_simulations_turn": 5,
            "n_simulations_flop": 5,
            "max_memory_gb": min(usable_gb, 15),
            "description": "Low quality - fast generation, minimal memory"
        },
        "medium": {
            "n_river_clusters": 200,
            "n_turn_clusters": 200,
            "n_flop_clusters": 200,
            "n_simulations_river": 10,
            "n_simulations_turn": 10,
            "n_simulations_flop": 10,
            "max_memory_gb": min(usable_gb, 30),
            "description": "Medium quality - balanced speed/quality"
        },
        "high": {
            "n_river_clusters": 300,
            "n_turn_clusters": 300,
            "n_flop_clusters": 300,
            "n_simulations_river": 15,
            "n_simulations_turn": 15,
            "n_simulations_flop": 15,
            "max_memory_gb": min(usable_gb, 45),
            "description": "High quality - good for serious training"
        },
        "ultra": {
            "n_river_clusters": 500,
            "n_turn_clusters": 400,  # Reduced from 500 to fit memory
            "n_flop_clusters": 400,   # Reduced from 500 to fit memory
            "n_simulations_river": 20,
            "n_simulations_turn": 15,  # Reduced to save memory
            "n_simulations_flop": 15,  # Reduced to save memory
            "max_memory_gb": min(usable_gb, 50),
            "description": "Ultra quality - best possible within memory limits"
        }
    }
    
    return settings.get(quality_mode, settings["medium"])


@click.command()
@click.option(
    "--quality",
    type=click.Choice(["low", "medium", "high", "ultra", "auto"]),
    default="auto",
    help="Quality mode for clustering. 'auto' selects based on available RAM."
)
@click.option(
    "--max_memory_gb",
    type=float,
    default=None,
    help="Maximum memory to use in GB. If not set, uses 80% of available."
)
@click.option(
    "--low_card_rank",
    default=2,
    help="Starting card rank (2-14). Default 2 for full deck."
)
@click.option(
    "--high_card_rank",
    default=14,
    help="Ending card rank (2-14). Default 14 (Ace) for full deck."
)
@click.option(
    "--save_dir",
    default=".",
    help="Directory to save LUT files."
)
@click.option(
    "--n_river_clusters",
    type=int,
    default=None,
    help="Override number of river clusters."
)
@click.option(
    "--n_turn_clusters",
    type=int,
    default=None,
    help="Override number of turn clusters."
)
@click.option(
    "--n_flop_clusters",
    type=int,
    default=None,
    help="Override number of flop clusters."
)
@click.option(
    "--n_simulations_river",
    type=int,
    default=None,
    help="Override river simulations."
)
@click.option(
    "--n_simulations_turn",
    type=int,
    default=None,
    help="Override turn simulations."
)
@click.option(
    "--n_simulations_flop",
    type=int,
    default=None,
    help="Override flop simulations."
)
@click.option(
    "--resume/--no-resume",
    default=True,
    help="Resume from checkpoint if available."
)
@click.option(
    "--use_disk_cache/--no-disk-cache",
    default=True,
    help="Use disk for intermediate storage (recommended for large datasets)."
)
def memory_cluster(
    quality: str,
    max_memory_gb: float,
    low_card_rank: int,
    high_card_rank: int,
    save_dir: str,
    n_river_clusters: int,
    n_turn_clusters: int,
    n_flop_clusters: int,
    n_simulations_river: int,
    n_simulations_turn: int,
    n_simulations_flop: int,
    resume: bool,
    use_disk_cache: bool,
):
    """
    Run memory-efficient clustering for poker AI.
    
    This tool automatically adapts to your system's available memory
    and provides checkpoint/resume capability for long-running processes.
    """
    # Get system information
    total_ram_gb = psutil.virtual_memory().total / (1024**3)
    available_gb = get_available_memory_gb()
    cpu_count = os.cpu_count() or 4
    
    log.info("=" * 60)
    log.info("MEMORY-EFFICIENT POKER AI CLUSTERING")
    log.info("=" * 60)
    log.info(f"System Information:")
    log.info(f"  Total RAM: {total_ram_gb:.1f} GB")
    log.info(f"  Available RAM: {available_gb:.1f} GB")
    log.info(f"  CPU cores: {cpu_count}")
    log.info("")
    
    # Get recommended settings
    if max_memory_gb is None:
        max_memory_gb = available_gb * 0.8
    
    settings = get_recommended_settings(available_gb, quality)
    
    # Override with custom values if provided
    if n_river_clusters is not None:
        settings["n_river_clusters"] = n_river_clusters
    if n_turn_clusters is not None:
        settings["n_turn_clusters"] = n_turn_clusters
    if n_flop_clusters is not None:
        settings["n_flop_clusters"] = n_flop_clusters
    if n_simulations_river is not None:
        settings["n_simulations_river"] = n_simulations_river
    if n_simulations_turn is not None:
        settings["n_simulations_turn"] = n_simulations_turn
    if n_simulations_flop is not None:
        settings["n_simulations_flop"] = n_simulations_flop
    
    # Update max memory if custom value provided
    if max_memory_gb:
        settings["max_memory_gb"] = min(max_memory_gb, available_gb * 0.9)
    
    log.info(f"Quality Mode: {quality.upper()}")
    log.info(f"  {settings['description']}")
    log.info("")
    log.info("Settings:")
    log.info(f"  Card range: {low_card_rank}-{high_card_rank}")
    log.info(f"  River clusters: {settings['n_river_clusters']}")
    log.info(f"  Turn clusters: {settings['n_turn_clusters']}")
    log.info(f"  Flop clusters: {settings['n_flop_clusters']}")
    log.info(f"  River simulations: {settings['n_simulations_river']}")
    log.info(f"  Turn simulations: {settings['n_simulations_turn']}")
    log.info(f"  Flop simulations: {settings['n_simulations_flop']}")
    log.info(f"  Max memory: {settings['max_memory_gb']:.1f} GB")
    log.info(f"  Disk cache: {use_disk_cache}")
    log.info(f"  Resume: {resume}")
    log.info("")
    
    # Estimate processing
    if low_card_rank == 2 and high_card_rank == 14:
        log.info("Dataset size (52-card Texas Hold'em):")
        log.info("  River combinations: ~133 million")
        log.info("  Turn combinations: ~20 million")
        log.info("  Flop combinations: ~2.6 million")
    elif low_card_rank == 10 and high_card_rank == 14:
        log.info("Dataset size (20-card Short Deck):")
        log.info("  River combinations: ~2.4 million")
        log.info("  Turn combinations: ~270k")
        log.info("  Flop combinations: ~23k")
    
    log.info("")
    log.info("Starting clustering process...")
    log.info("=" * 60)
    
    # Create builder
    builder = MemoryEfficientLutBuilder(
        n_simulations_river=settings["n_simulations_river"],
        n_simulations_turn=settings["n_simulations_turn"],
        n_simulations_flop=settings["n_simulations_flop"],
        low_card_rank=low_card_rank,
        high_card_rank=high_card_rank,
        save_dir=save_dir,
        max_memory_gb=settings["max_memory_gb"],
        use_disk_cache=use_disk_cache,
    )
    
    # Run clustering
    try:
        builder.compute(
            n_river_clusters=settings["n_river_clusters"],
            n_turn_clusters=settings["n_turn_clusters"],
            n_flop_clusters=settings["n_flop_clusters"],
        )
        
        log.info("")
        log.info("=" * 60)
        log.info("✅ CLUSTERING COMPLETED SUCCESSFULLY!")
        log.info("=" * 60)
        log.info(f"Output files saved to: {save_dir}")
        log.info("  - card_info_lut.joblib")
        log.info("  - centroids.joblib")
        
    except KeyboardInterrupt:
        log.warning("")
        log.warning("Process interrupted by user!")
        log.warning("Progress has been saved. Run again with --resume to continue.")
    except Exception as e:
        log.error(f"Error during clustering: {e}")
        log.error("Progress has been saved. You can resume from checkpoint.")
        raise


if __name__ == "__main__":
    memory_cluster()
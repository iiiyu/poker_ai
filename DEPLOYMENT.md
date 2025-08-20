# Deployment Guide for Poker AI

This guide covers deployment, configuration, and operational procedures for the Poker AI system.

## Quick Start

### Development Deployment
```bash
# Build and run hybrid container
docker build -f Dockerfile.hybrid -t poker-ai:dev .
docker run -it --rm poker-ai:dev

# Or use docker-compose for development
docker-compose up -d
```

### Production Deployment
```bash
# Use pre-built images from Docker Hub
docker-compose -f docker-compose.prod.yml up -d

# Or build from source
./scripts/build_release.sh
docker build -f Dockerfile.hybrid -t poker-ai:prod .
```

## Container Images

### Hybrid Image (Python + Zig)
- **Image**: `pokerai/poker-ai:latest`
- **Size**: ~300MB
- **Contains**: Full Python environment + Zig clustering binary
- **Use case**: Complete AI training and inference
- **Startup time**: <1 second
- **Memory usage**: 100-500MB idle, up to 2GB during training

### Zig-only Image (Clustering)
- **Image**: `pokerai/poker-clustering:latest` 
- **Size**: ~50MB
- **Contains**: Only Zig clustering binary + SQLite
- **Use case**: Microservice architecture, clustering-only workloads
- **Startup time**: <0.5 seconds
- **Memory usage**: 50-200MB

## Installation Methods

### 1. PyPI Package
```bash
pip install poker-ai

# Verify installation
python -c "import poker_ai; print('Success')"
poker_ai --help
```

### 2. Docker Containers
```bash
# Pull and run hybrid image
docker pull pokerai/poker-ai:latest
docker run -it pokerai/poker-ai:latest

# Pull and run clustering-only image
docker pull pokerai/poker-clustering:latest
docker run -it pokerai/poker-clustering:latest poker_clustering --help
```

### 3. Native Binaries
Download platform-specific binaries from [GitHub Releases](https://github.com/fedden/poker_ai/releases):
- `poker-clustering-linux-x86_64` - Linux x86_64
- `poker-clustering-macos-x86_64` - macOS Intel
- `poker-clustering-macos-aarch64` - macOS Apple Silicon
- `poker-clustering-windows-x86_64.exe` - Windows x86_64

```bash
# Linux/macOS installation
chmod +x poker-clustering-*
sudo mv poker-clustering-* /usr/local/bin/poker_clustering

# Verify
poker_clustering --help
```

### 4. Build from Source
```bash
git clone https://github.com/fedden/poker_ai.git
cd poker_ai

# Build everything
./scripts/build_release.sh

# Cross-compile Zig binaries
./scripts/cross_compile.sh

# Build specific components
./scripts/build_release.sh python  # Python package only
./scripts/build_release.sh zig     # Zig binary only
```

## Configuration

### Environment Variables

#### Core Settings
- `POKER_AI_DATA_DIR=/app/data` - Data storage directory
- `POKER_AI_MODEL_DIR=/app/models` - Trained model storage
- `POKER_AI_LOG_DIR=/app/logs` - Log file directory
- `POKER_AI_LOG_LEVEL=INFO` - Logging level (DEBUG, INFO, WARN, ERROR)

#### Performance Settings
- `POKER_AI_WORKERS=4` - Number of worker processes
- `POKER_AI_MEMORY_LIMIT=2G` - Memory limit for clustering
- `POKER_AI_BATCH_SIZE=1000` - Batch size for training

#### Clustering Settings
- `ZIG_CLUSTERING_DB_PATH=/data/clustering.db` - SQLite database path
- `ZIG_CLUSTERING_THREADS=4` - Number of threads for clustering

### Configuration Files

#### clustering_configs.yaml
```yaml
# Copy and modify from clustering_configs.yaml
memory_limit_gb: 4
batch_size: 1000
checkpoint_interval: 10000
use_zig_clustering: true
```

#### Docker Environment
```bash
# Create .env file for docker-compose
cat > .env << EOF
POKER_AI_LOG_LEVEL=INFO
POKER_AI_WORKERS=4
MEMORY_LIMIT=2G
EOF
```

## Production Deployment

### Prerequisites
```bash
# Create required directories
mkdir -p data/{poker,models,clustering} logs monitoring

# Set permissions
sudo chown -R 1000:1000 data logs
chmod 755 data logs monitoring
```

### Deploy with Docker Compose
```bash
# Production deployment
docker-compose -f docker-compose.prod.yml up -d

# Scale services
docker-compose -f docker-compose.prod.yml up -d --scale poker-ai=3

# Check status
docker-compose -f docker-compose.prod.yml ps
```

### Resource Requirements

#### Minimum (Development)
- **CPU**: 2 cores
- **Memory**: 4GB RAM
- **Storage**: 10GB
- **Network**: 1Mbps

#### Recommended (Production)
- **CPU**: 8 cores
- **Memory**: 16GB RAM  
- **Storage**: 100GB SSD
- **Network**: 10Mbps

#### High-Performance (Training)
- **CPU**: 16+ cores
- **Memory**: 32GB+ RAM
- **Storage**: 500GB+ NVMe SSD
- **Network**: 100Mbps+

## Monitoring

### Health Checks
```bash
# Application health
curl http://localhost:8080/health

# Container health
docker ps  # Check STATUS column

# Service logs
docker-compose -f docker-compose.prod.yml logs -f poker-ai
```

### Metrics and Monitoring
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000 (admin/admin123)
- **Application logs**: `logs/` directory

### Key Metrics to Monitor
- **Memory usage**: Should stay under configured limits
- **CPU utilization**: Should be <80% under normal load
- **Response time**: API calls should complete <1s
- **Error rate**: Should be <1% under normal conditions
- **Training progress**: Monitor clustering completion %

## Operations

### Backup Procedures
```bash
# Backup data volumes
docker run --rm -v poker_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/poker-data-$(date +%Y%m%d).tar.gz /data

# Backup models
docker run --rm -v poker_models:/models -v $(pwd):/backup \
  alpine tar czf /backup/poker-models-$(date +%Y%m%d).tar.gz /models
```

### Update Procedures
```bash
# 1. Backup current data
./scripts/backup.sh

# 2. Pull latest images
docker-compose -f docker-compose.prod.yml pull

# 3. Rolling update (zero downtime)
docker-compose -f docker-compose.prod.yml up -d --no-deps poker-ai

# 4. Verify deployment
curl http://localhost:8080/health
```

### Scaling
```bash
# Horizontal scaling
docker-compose -f docker-compose.prod.yml up -d --scale poker-ai=5

# Load balancing is handled by nginx automatically
```

### Troubleshooting

#### Common Issues

**Container won't start**
```bash
# Check logs
docker-compose -f docker-compose.prod.yml logs poker-ai

# Check resources
docker stats

# Check disk space
df -h
```

**High memory usage**
```bash
# Check memory configuration
docker exec poker-ai-app env | grep MEMORY

# Restart with lower limits
docker-compose -f docker-compose.prod.yml restart poker-ai
```

**Slow clustering performance**
```bash
# Check Zig binary is being used
docker exec poker-ai-app which poker_clustering

# Check thread configuration
docker exec poker-ai-app poker_clustering --help
```

#### Performance Optimization

**CPU Optimization**
- Increase `POKER_AI_WORKERS` to match CPU cores
- Use `--cpus` limit to prevent resource contention
- Enable CPU affinity for clustering tasks

**Memory Optimization**  
- Tune `memory_limit_gb` in clustering config
- Use memory-mapped files for large datasets
- Enable swap for training workloads

**I/O Optimization**
- Use SSD storage for data volumes
- Configure appropriate batch sizes
- Enable compression for network traffic

## Security

### Container Security
- Containers run as non-root user (UID 1000)
- Read-only root filesystem where possible
- Minimal attack surface (Alpine/distroless base)
- Resource limits prevent DoS attacks

### Network Security
- All services on internal bridge network
- Only required ports exposed externally
- Rate limiting on API endpoints
- Security headers in nginx configuration

### Data Security
- Sensitive data in mounted volumes only
- No credentials in container images
- Use Docker secrets for production passwords
- Regular security updates via CI/CD

## Disaster Recovery

### Backup Strategy
- **Daily**: Automated data backups
- **Weekly**: Full system snapshots
- **Monthly**: Offsite backup verification

### Recovery Procedures
1. **Data corruption**: Restore from latest backup
2. **Container failure**: Restart service automatically
3. **Host failure**: Migrate to standby host
4. **Complete disaster**: Deploy from infrastructure as code

### RTO/RPO Targets
- **Recovery Time Objective (RTO)**: <30 minutes
- **Recovery Point Objective (RPO)**: <1 hour data loss

## Support

### Getting Help
- **Documentation**: https://poker-ai.readthedocs.io
- **Issues**: https://github.com/fedden/poker_ai/issues
- **Discussions**: https://github.com/fedden/poker_ai/discussions

### Log Collection
```bash
# Collect all logs for support
./scripts/collect_logs.sh

# This creates a poker-ai-logs-YYYYMMDD.tar.gz file
```

### Performance Profiling
```bash
# Enable debug logging
export POKER_AI_LOG_LEVEL=DEBUG

# Run with profiling
docker run --rm -it \
  -e POKER_AI_LOG_LEVEL=DEBUG \
  pokerai/poker-ai:latest \
  python -m cProfile -o profile.stats -m poker_ai.cli.runner
```
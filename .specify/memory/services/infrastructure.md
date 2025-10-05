# Infrastructure Services Details

**Load When**: Database schema changes, caching strategy updates, or infrastructure optimization

## 1. ai-micro-postgres (Port 5432)

### Purpose

Shared PostgreSQL database infrastructure with service-specific databases

### Technology

- PostgreSQL 15+
- Docker containerized

### Databases

#### authdb

**Owner**: ai-micro-api-auth
**Purpose**: Authentication data

**Tables**:

- `users`: id (UUID PK), email (UNIQUE), hashed_password, roles (ARRAY), created_at, updated_at

**Indexes**:

- PRIMARY KEY on id
- UNIQUE INDEX on email
- TODO: Add index on roles for role-based queries

#### apidb

**Owner**: ai-micro-api-user
**Purpose**: User profiles

**Tables**:

- `profiles`: user_id (UUID PK, FK to authdb.users), first_name, last_name, email, created_at, updated_at

**Indexes**:

- PRIMARY KEY on user_id
- INDEX on email for lookups

#### admindb

**Owner**: ai-micro-api-admin
**Purpose**: Documents, knowledge bases

**Tables**:

- `documents`: id (UUID PK), title, file_path, ocr_result (JSONB), hierarchical_elements (JSONB), created_at, updated_at
- `knowledge_bases`: id (UUID PK), name, description, user_id (UUID), created_at, updated_at
- `kb_documents`: kb_id (UUID, FK), document_id (UUID, FK), order (INT), PRIMARY KEY (kb_id, document_id)

**Indexes**:

- PRIMARY KEY on each table's id
- INDEX on knowledge_bases(user_id)
- INDEX on kb_documents(kb_id)
- TODO: GIN index on documents.ocr_result for full-text search

### Connection Patterns

- Each service connects to its dedicated database
- No cross-database joins (enforced via application logic)
- Connection strings use `host.docker.internal` for Docker networking

### Common Operations

```bash
# Connect to PostgreSQL
docker exec postgres psql -U postgres

# List databases
docker exec postgres psql -U postgres -c "\l"

# Check tables in authdb
docker exec postgres psql -U postgres -d authdb -c "\dt"

# Add missing columns (example)
docker exec postgres psql -U postgres -d apidb -c "ALTER TABLE profiles ADD COLUMN IF NOT EXISTS first_name TEXT;"

# Check table sizes
docker exec postgres psql -U postgres -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) AS size FROM pg_database;"
```

### Schema Migration Strategy

- Use Alembic for schema versioning
- Migration files stored in each service's repository
- Apply migrations before service startup

### Backup & Recovery

- Daily automated backups (TODO: implement)
- Point-in-time recovery enabled
- Retention: 30 days

## 2. ai-micro-redis (Port 6379)

### Purpose

Shared caching and session management

### Technology

- Redis 7+
- Docker containerized
- Password-protected

### Use Cases

#### Sessions

**Pattern**: `session:<user_id>:<session_id>`
**TTL**: 30 days
**Data**: User session metadata (JSON)

#### Token Blacklist

**Pattern**:

- Access tokens: `blacklist:access:<jti>`
- Refresh tokens: `blacklist:refresh:<jti>`

**TTL**: Token expiration time
**Data**: Timestamp of blacklisting

#### Profile Caching

**Pattern**: `profile:<user_id>`
**TTL**: 300 seconds (5 minutes)
**Data**: User profile JSON

#### Document Processing State

**Pattern**: `doc:processing:<document_id>`
**TTL**: 3600 seconds (1 hour)
**Data**: Processing status, progress percentage

### Configuration

- **Eviction Policy**: allkeys-lru (evict least recently used keys when maxmemory reached)
- **Max Memory**: 2GB
- **Persistence**: RDB snapshots every 300 seconds if 10+ keys changed

### Common Operations

```bash
# Connect to Redis
docker exec redis redis-cli -a "${REDIS_PASSWORD}"

# Check connection
docker exec redis redis-cli -a "${REDIS_PASSWORD}" ping

# Get key info
docker exec redis redis-cli -a "${REDIS_PASSWORD}" GET session:user123:abc

# Check memory usage
docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO memory

# List all keys (use cautiously in production)
docker exec redis redis-cli -a "${REDIS_PASSWORD}" KEYS '*'

# Check key TTL
docker exec redis redis-cli -a "${REDIS_PASSWORD}" TTL blacklist:access:xyz
```

### Performance Tuning

- Connection pooling in all services (10-20 connections)
- Pipeline for batch operations
- Use SCAN instead of KEYS for production
- Monitor slow queries with SLOWLOG

### Security

- Password authentication required
- Network isolation (only accessible from service containers)
- Regular password rotation (TODO: automate)

## Infrastructure Development Workflow

### Database Optimization Example

When optimizing queries:

1. Identify slow queries using PostgreSQL logs
2. Run EXPLAIN ANALYZE on problematic queries
3. Add indexes where needed
4. Update service code to utilize indexes
5. Verify performance improvement

### Redis Optimization Example

When improving caching:

1. Analyze cache hit/miss ratios
2. Adjust TTLs based on data volatility
3. Use Redis MONITOR to observe key access patterns
4. Implement cache warming for frequently accessed data

### Monitoring

- PostgreSQL: pg_stat_statements for query performance
- Redis: INFO stats for operations per second
- TODO: Set up Prometheus + Grafana for infrastructure metrics

## Known Issues

### PostgreSQL

- Some tables missing indexes for common queries (users.roles, documents.ocr_result)
- No automated backup strategy yet

### Redis

- Eviction policy not explicitly configured (defaults to noeviction)
- No monitoring/alerting on memory usage

### Migration Plan

See project-context-core.md "Known Technical Debt" section for prioritization

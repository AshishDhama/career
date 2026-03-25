#!/bin/bash
# Start development environment

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG="${ROOT}/../zig/zig"

echo "Starting Career dev environment..."

# Start PostgreSQL
docker compose -f "$ROOT/docker-compose.yml" up -d db
echo "Waiting for PostgreSQL..."
sleep 2

# Start Zig backend in background
cd "$ROOT/backend"
$ZIG build run &
BACKEND_PID=$!
echo "Backend started (PID: $BACKEND_PID)"

# Start React frontend dev server
cd "$ROOT/frontend"
npm run dev &
FRONTEND_PID=$!
echo "Frontend started (PID: $FRONTEND_PID)"

echo ""
echo "Career platform running:"
echo "  Frontend: http://localhost:5173"
echo "  Backend:  http://localhost:8080"
echo "  DB:       localhost:5432"
echo ""
echo "Press Ctrl+C to stop all services"

cleanup() {
    echo "Stopping services..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    docker compose -f "$ROOT/docker-compose.yml" stop db
}
trap cleanup EXIT

wait

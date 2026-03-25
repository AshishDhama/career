const std = @import("std");

const c = @cImport({
    @cInclude("libpq-fe.h");
});

pub const DbError = error{
    ConnectionFailed,
    QueryFailed,
    NoRows,
    OutOfMemory,
};

pub const Row = struct {
    result: *c.PGresult,
    row: c_int,

    pub fn get(self: Row, col: c_int) ?[]const u8 {
        if (c.PQgetisnull(self.result, self.row, col) == 1) return null;
        const val = c.PQgetvalue(self.result, self.row, col);
        const len = c.PQgetlength(self.result, self.row, col);
        return val[0..@intCast(len)];
    }
};

pub const Result = struct {
    result: *c.PGresult,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Result) void {
        c.PQclear(self.result);
    }

    pub fn rowCount(self: Result) usize {
        return @intCast(c.PQntuples(self.result));
    }

    pub fn row(self: Result, i: usize) Row {
        return .{ .result = self.result, .row = @intCast(i) };
    }
};

pub const Pool = struct {
    conn: *c.PGconn,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, database_url: []const u8) DbError!Pool {
        const url_z = allocator.dupeZ(u8, database_url) catch return DbError.OutOfMemory;
        defer allocator.free(url_z);

        const conn = c.PQconnectdb(url_z.ptr) orelse return DbError.ConnectionFailed;

        if (c.PQstatus(conn) != c.CONNECTION_OK) {
            std.debug.print("DB connection failed: {s}\n", .{c.PQerrorMessage(conn)});
            c.PQfinish(conn);
            return DbError.ConnectionFailed;
        }

        std.debug.print("Connected to PostgreSQL\n", .{});
        return Pool{
            .conn = conn,
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Pool) void {
        c.PQfinish(self.conn);
    }

    pub fn query(self: *Pool, sql: []const u8, params: []const []const u8) DbError!Result {
        self.mutex.lock();
        defer self.mutex.unlock();

        const sql_z = self.allocator.dupeZ(u8, sql) catch return DbError.OutOfMemory;
        defer self.allocator.free(sql_z);

        var result: *c.PGresult = undefined;

        if (params.len == 0) {
            result = c.PQexec(self.conn, sql_z.ptr) orelse return DbError.QueryFailed;
        } else {
            // Build C-string param array
            var param_ptrs = self.allocator.alloc([*c]const u8, params.len) catch return DbError.OutOfMemory;
            defer self.allocator.free(param_ptrs);
            var param_strs = self.allocator.alloc([:0]u8, params.len) catch return DbError.OutOfMemory;
            defer {
                for (param_strs) |s| self.allocator.free(s);
                self.allocator.free(param_strs);
            }
            for (params, 0..) |p, i| {
                param_strs[i] = self.allocator.dupeZ(u8, p) catch return DbError.OutOfMemory;
                param_ptrs[i] = param_strs[i].ptr;
            }

            result = c.PQexecParams(
                self.conn,
                sql_z.ptr,
                @intCast(params.len),
                null,
                param_ptrs.ptr,
                null,
                null,
                0,
            ) orelse return DbError.QueryFailed;
        }

        const status = c.PQresultStatus(result);
        if (status != c.PGRES_TUPLES_OK and status != c.PGRES_COMMAND_OK) {
            std.debug.print("Query error: {s}\n", .{c.PQerrorMessage(self.conn)});
            c.PQclear(result);
            return DbError.QueryFailed;
        }

        return Result{ .result = result, .allocator = self.allocator };
    }

    pub fn queryOne(self: *Pool, sql: []const u8, params: []const []const u8) DbError!Row {
        var result = try self.query(sql, params);
        if (result.rowCount() == 0) {
            result.deinit();
            return DbError.NoRows;
        }
        // Note: caller must call PQclear manually — or we store the result
        // For simplicity, we return the first row. Caller owns the result.
        return result.row(0);
    }
};

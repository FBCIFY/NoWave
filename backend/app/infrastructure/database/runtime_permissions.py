from psycopg import sql


def grant_runtime_table_permissions(connection, role_name="nowave_runtime"):
    """Shared by deployment and tests using a role without owner privileges."""
    role = sql.Identifier(role_name)
    connection.execute(
        sql.SQL("GRANT USAGE ON SCHEMA nowave, public TO {}").format(role)
    )
    connection.execute(
        sql.SQL(
            "GRANT SELECT, INSERT, UPDATE, DELETE ON nowave.users, nowave.reports, nowave.boats TO {}"
        ).format(role)
    )
    connection.execute(
        sql.SQL("GRANT SELECT, INSERT, UPDATE ON nowave.report_photos TO {}").format(
            role
        )
    )
    connection.execute(
        sql.SQL("GRANT SELECT, INSERT ON nowave.report_positioning TO {}").format(role)
    )

    connection.execute(
        sql.SQL(
            "GRANT SELECT, INSERT, UPDATE "
            "ON nowave.devices TO {}"
        ).format(role)
    )

    connection.execute(
        sql.SQL(
            "GRANT SELECT, INSERT, UPDATE, DELETE "
            "ON nowave.device_positions TO {}"
        ).format(role)
    )

    connection.execute(
        sql.SQL(
            "GRANT SELECT, UPDATE, DELETE "
            "ON nowave.notifications TO {}"
        ).format(role)
    )

-- scenario_2_202405590.sql
DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;
DROP PROCEDURE IF EXISTS reserve_workstations(VARCHAR, INT, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

CREATE TABLE lab_sessions (
    session_id SERIAL PRIMARY KEY,
    session_name VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    lecturer VARCHAR(100) NOT NULL,
    session_id INT NOT NULL REFERENCES lab_sessions(session_id),
    num_workstations INT NOT NULL CHECK (num_workstations > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'RESERVED',
    reservation_date DATE NOT NULL DEFAULT CURRENT_DATE
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
('Database Lab', 1),
('Networking Lab', 3),
('Programming Lab', 0);

-- 2. IF ELSIF ELSE
DO $$
DECLARE v_avail INT;
BEGIN
    SELECT available_workstations INTO v_avail
    FROM lab_sessions WHERE session_id = 1;

    IF v_avail = 0 THEN
        RAISE NOTICE 'Session 1 is FULL.';
    ELSIF v_avail <= 2 THEN
        RAISE NOTICE 'Session 1 is NEARLY FULL. Workstations left: %', v_avail;
    ELSE
        RAISE NOTICE 'Session 1 has ENOUGH workstations. Left: %', v_avail;
    END IF;
END $$;

-- 3a. WHILE
DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', i;
        i := i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR
DO $$
BEGIN
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- 4. reserve_workstations
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_lecturer VARCHAR,
    p_session_id INT,
    p_num_workstations INT
)
LANGUAGE plpgsql AS $$
DECLARE v_avail INT;
BEGIN
    IF p_num_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Must be greater than zero.', p_num_workstations;
    END IF;

    SELECT available_workstations INTO v_avail
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session ID % does not exist.', p_session_id;
    END IF;

    IF v_avail < p_num_workstations THEN
        RAISE EXCEPTION 'Not enough workstations in session %. Available: %, requested: %',
            p_session_id, v_avail, p_num_workstations;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_num_workstations
    WHERE session_id = p_session_id;

    INSERT INTO reservations (lecturer, session_id, num_workstations, status)
    VALUES (p_lecturer, p_session_id, p_num_workstations, 'RESERVED');

    RAISE NOTICE 'Reservation recorded for lecturer %, session %, workstations %.',
        p_lecturer, p_session_id, p_num_workstations;
END;
$$;

-- 5. Calls
CALL reserve_workstations('Dr Banda', 1, 1);
CALL reserve_workstations('Dr Phiri', 2, 2);

DO $$
BEGIN
    CALL reserve_workstations('Dr Mwale', 2, 999);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Caught expected error: %', SQLERRM;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR(20);
    v_session_id INT;
    v_num INT;
BEGIN
    SELECT status, session_id, num_workstations
    INTO v_status, v_session_id, v_num
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation ID % does not exist.', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled. Workstations will NOT be released again.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_num
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. Released % workstations.', p_reservation_id, v_num;
END;
$$;

CALL cancel_reservation(1);
CALL cancel_reservation(1); -- second must not release again

-- 7. Explicit cursor
DO $$
DECLARE
    cur CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 2
        ORDER BY available_workstations;
    rec RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low workstations: Session ID %, Name %, Left %',
            rec.session_id, rec.session_name, rec.available_workstations;
    END LOOP;
    CLOSE cur;
END $$;

-- 8. Zero request
DO $$
BEGIN
    CALL reserve_workstations('Dr Zero', 2, 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Invalid quantity handled: %', SQLERRM;
END $$;

-- 9. Final query
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
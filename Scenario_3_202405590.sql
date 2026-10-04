-- scenario_3_202405590.sql
DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;
DROP PROCEDURE IF EXISTS allocate_room(VARCHAR, INT);
DROP PROCEDURE IF EXISTS check_out(INT);

CREATE TABLE hostel_rooms (
    room_id SERIAL PRIMARY KEY,
    room_number VARCHAR(10) NOT NULL,
    available_bed_spaces INT NOT NULL CHECK (available_bed_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id INT NOT NULL REFERENCES hostel_rooms(room_id),
    status VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED',
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE
);

INSERT INTO hostel_rooms (room_number, available_bed_spaces) VALUES
('A101', 1),
('B202', 3),
('C303', 0);

-- 2. IF ELSIF ELSE
DO $$
DECLARE v_spaces INT;
BEGIN
    SELECT available_bed_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = 1;

    IF v_spaces = 0 THEN
        RAISE NOTICE 'Room 1 is FULL.';
    ELSIF v_spaces = 1 THEN
        RAISE NOTICE 'Room 1 has ONE space left.';
    ELSE
        RAISE NOTICE 'Room 1 has SEVERAL spaces left: %', v_spaces;
    END IF;
END $$;

-- 3a. WHILE
DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', i;
        i := i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR
DO $$
BEGIN
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', i;
    END LOOP;
END $$;

-- 4. allocate_room
CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id INT
)
LANGUAGE plpgsql AS $$
DECLARE v_spaces INT;
BEGIN
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid student number: cannot be blank.';
    END IF;

    SELECT available_bed_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room ID % does not exist.', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE EXCEPTION 'Room % is full. No bed space available.', p_room_id;
    END IF;

    UPDATE hostel_rooms
    SET available_bed_spaces = available_bed_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (p_student_number, p_room_id, 'ALLOCATED');

    RAISE NOTICE 'Allocated room % to student %.', p_room_id, p_student_number;
END;
$$;

-- 5. Calls
CALL allocate_room('STU001', 1);
CALL allocate_room('STU002', 2);

DO $$
BEGIN
    CALL allocate_room('STU003', 1); -- room 1 is now full
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Caught expected error: %', SQLERRM;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR(20);
    v_room_id INT;
BEGIN
    SELECT status, room_id
    INTO v_status, v_room_id
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation ID % does not exist.', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETED' THEN
        RAISE NOTICE 'Allocation % already completed. Bed space will NOT be released again.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETED' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms
    SET available_bed_spaces = available_bed_spaces + 1
    WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % checked out. Released 1 bed space in room %.',
        p_allocation_id, v_room_id;
END;
$$;

CALL check_out(1);
CALL check_out(1); -- second must not release again

-- 7. Explicit cursor
DO $$
DECLARE
    cur CURSOR FOR
        SELECT room_id, room_number, available_bed_spaces
        FROM hostel_rooms
        WHERE available_bed_spaces <= 1
        ORDER BY available_bed_spaces;
    rec RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full/nearly full room: ID %, Number %, Spaces %',
            rec.room_id, rec.room_number, rec.available_bed_spaces;
    END LOOP;
    CLOSE cur;
END $$;

-- 8. Blank student number
DO $$
BEGIN
    CALL allocate_room('', 2);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Invalid input handled: %', SQLERRM;
END $$;

-- 9. Final query
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
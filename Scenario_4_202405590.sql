-- scenario_4_202405590.sql
DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP PROCEDURE IF EXISTS dispense_medicine(VARCHAR, INT, INT);
DROP PROCEDURE IF EXISTS reverse_dispensing(INT);

CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    medicine_id INT NOT NULL REFERENCES medicines(medicine_id),
    quantity INT NOT NULL CHECK (quantity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'DISPENSED',
    dispensed_date DATE NOT NULL DEFAULT CURRENT_DATE
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
('Paracetamol', 2),
('Amoxicillin', 5),
('Ibuprofen', 0);

-- 2. IF ELSIF ELSE
DO $$
DECLARE v_stock INT;
BEGIN
    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = 1;

    IF v_stock = 0 THEN
        RAISE NOTICE 'Medicine 1 is OUT OF STOCK.';
    ELSIF v_stock <= 2 THEN
        RAISE NOTICE 'Medicine 1 is LOW ON STOCK. Quantity: %', v_stock;
    ELSE
        RAISE NOTICE 'Medicine 1 is SUFFICIENTLY STOCKED. Quantity: %', v_stock;
    END IF;
END $$;

-- 3a. WHILE
DO $$
DECLARE i INT := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Stock review day %', i;
        i := i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR
DO $$
BEGIN
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', i;
    END LOOP;
END $$;

-- 4. dispense_medicine
CREATE OR REPLACE PROCEDURE dispense_medicine(
    p_student_number VARCHAR,
    p_medicine_id INT,
    p_quantity INT
)
LANGUAGE plpgsql AS $$
DECLARE v_stock INT;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Must be greater than zero.', p_quantity;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine ID % does not exist.', p_medicine_id;
    END IF;

    IF v_stock < p_quantity THEN
        RAISE EXCEPTION 'Not enough stock for medicine %. Available: %, requested: %',
            p_medicine_id, v_stock, p_quantity;
    END IF;

    UPDATE medicines
    SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (student_number, medicine_id, quantity, status)
    VALUES (p_student_number, p_medicine_id, p_quantity, 'DISPENSED');

    RAISE NOTICE 'Dispensed % of medicine % to student %.',
        p_quantity, p_medicine_id, p_student_number;
END;
$$;

-- 5. Calls
CALL dispense_medicine('STU001', 1, 2); -- valid
CALL dispense_medicine('STU002', 2, 3); -- valid

DO $$
BEGIN
    CALL dispense_medicine('STU003', 2, 999); -- exceeds stock
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Caught expected error: %', SQLERRM;
END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 6. reverse_dispensing
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR(20);
    v_medicine_id INT;
    v_quantity INT;
BEGIN
    SELECT status, medicine_id, quantity
    INTO v_status, v_medicine_id, v_quantity
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist.', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed. Stock will NOT be restored again.', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines
    SET stock_quantity = stock_quantity + v_quantity
    WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed. Restored % of medicine %.',
        p_record_id, v_quantity, v_medicine_id;
END;
$$;

CALL reverse_dispensing(1);
CALL reverse_dispensing(1); -- second must not restore again

-- 7. Explicit cursor
DO $$
DECLARE
    cur CURSOR FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines
        WHERE stock_quantity <= 2
        ORDER BY stock_quantity;
    rec RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock medicine: ID %, Name %, Stock %',
            rec.medicine_id, rec.medicine_name, rec.stock_quantity;
    END LOOP;
    CLOSE cur;
END $$;

-- 8. Negative quantity
DO $$
BEGIN
    CALL dispense_medicine('STU004', 2, -5);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Invalid input handled: %', SQLERRM;
END $$;

-- 9. Final query
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
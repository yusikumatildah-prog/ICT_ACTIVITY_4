-- File: scenario_1_202405590.sql
-- Scenario 1: Books table and book_loans table

-- Clean up old objects if re-running
DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;
DROP PROCEDURE IF EXISTS borrow_book(VARCHAR, INT, INT);
DROP PROCEDURE IF EXISTS return_book(INT);

-- 1. Create tables
CREATE TABLE books (
    book_id           SERIAL PRIMARY KEY,
    title             VARCHAR(100) NOT NULL,
    available_copies  INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    book_id        INT NOT NULL REFERENCES books(book_id),
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED',
    loan_date      DATE NOT NULL DEFAULT CURRENT_DATE
);

-- Add at least three books
INSERT INTO books (title, available_copies) VALUES
('Database Systems', 1),
('Programming Logic', 3),
('Networking Essentials', 0);

-- 2. IF ELSIF ELSE: report stock level for one book
DO $$
DECLARE
    v_copies INT;
BEGIN
    SELECT available_copies INTO v_copies
    FROM books
    WHERE book_id = 1;

    IF v_copies = 0 THEN
        RAISE NOTICE 'Book 1 is UNAVAILABLE.';
    ELSIF v_copies <= 2 THEN
        RAISE NOTICE 'Book 1 is LOW ON COPIES. Copies left: %', v_copies;
    ELSE
        RAISE NOTICE 'Book 1 is SUFFICIENTLY STOCKED. Copies left: %', v_copies;
    END IF;
END $$;

-- 3a. WHILE: three overdue reminder numbers
DO $$
DECLARE
    v_i INT := 1;
BEGIN
    WHILE v_i <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', v_i;
        v_i := v_i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR: three library shelf numbers
DO $$
BEGIN
    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number: %', i;
    END LOOP;
END $$;

-- 4. Create borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(
    p_student_number VARCHAR,
    p_book_id INT,
    p_quantity INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Quantity must be greater than zero.', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book ID % does not exist.', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE EXCEPTION 'Not enough copies for book ID %. Available: %, requested: %',
            p_book_id, v_available, p_quantity;
    END IF;

    UPDATE books
    SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (student_number, book_id, quantity, loan_status)
    VALUES (p_student_number, p_book_id, p_quantity, 'BORROWED');

    RAISE NOTICE 'Loan recorded for student %, book %, quantity %.',
        p_student_number, p_book_id, p_quantity;
END;
$$;

-- 5. Call borrow_book for two valid loans and one exceeding request
CALL borrow_book('STU001', 1, 1);   -- valid
CALL borrow_book('STU002', 2, 2);   -- valid

-- Exceeding request: catch exception so script continues
DO $$
BEGIN
    CALL borrow_book('STU003', 1, 999);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Caught expected error: %', SQLERRM;
END $$;

-- Query both tables to show recorded loans
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. Create return_book procedure
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status   VARCHAR(20);
    v_book_id  INT;
    v_quantity INT;
BEGIN
    SELECT loan_status, book_id, quantity
    INTO v_status, v_book_id, v_quantity
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan ID % does not exist.', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan ID % is already returned. Stock will NOT be restored again.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans
    SET loan_status = 'RETURNED'
    WHERE loan_id = p_loan_id;

    UPDATE books
    SET available_copies = available_copies + v_quantity
    WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan ID % returned. Restored % copies to book ID %.',
        p_loan_id, v_quantity, v_book_id;
END;
$$;

-- Call return_book twice for the same loan
CALL return_book(1);
CALL return_book(1);   -- must not restore copies again

-- 7. Explicit cursor: display books with few copies remaining
DO $$
DECLARE
    cur_books CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 2
        ORDER BY available_copies;

    rec RECORD;
BEGIN
    OPEN cur_books;

    LOOP
        FETCH cur_books INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock: Book ID %, Title %, Copies left %',
            rec.book_id, rec.title, rec.available_copies;
    END LOOP;

    CLOSE cur_books;
END $$;

-- 8. Try to borrow zero copies and handle invalid quantity
DO $$
BEGIN
    CALL borrow_book('STU004', 2, 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Invalid quantity handled successfully: %', SQLERRM;
END $$;

-- 9. Final query of both tables
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
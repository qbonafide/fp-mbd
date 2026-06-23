USE fp_rental_kendaraan;

DROP FUNCTION IF EXISTS fn_hitung_skor_risiko_pelanggan;

DELIMITER $$

CREATE FUNCTION fn_hitung_skor_risiko_pelanggan(
    p_id_pelanggan INT
)
RETURNS INT
DETERMINISTIC
BEGIN

    DECLARE v_skor INT DEFAULT 0;
    DECLARE v_jumlah INT DEFAULT 0;

    -- 1. Riwayat keterlambatan pengembalian
    SELECT COUNT(*)
    INTO v_jumlah
    FROM Kontrak_Sewa
    WHERE id_pelanggan = p_id_pelanggan
      AND status_sewa = 'Terlambat';

    SET v_skor = v_skor + (v_jumlah * 20);

    -- 2. Riwayat pembayaran menunggak
    SELECT COUNT(*)
    INTO v_jumlah
    FROM Pembayaran pb
    JOIN Kontrak_Sewa ks
        ON pb.id_sewa = ks.id_sewa
    WHERE ks.id_pelanggan = p_id_pelanggan
      AND pb.status_pembayaran = 'Menunggak';

    SET v_skor = v_skor + (v_jumlah * 15);

    -- 3. Pelanggaran geofence
    SELECT COUNT(*)
    INTO v_jumlah
    FROM Pelanggaran_Geofence pg
    JOIN Kontrak_Sewa ks
        ON pg.id_sewa = ks.id_sewa
    WHERE ks.id_pelanggan = p_id_pelanggan;

    SET v_skor = v_skor + (v_jumlah * 10);

    -- 4. Status akun pelanggan
    IF EXISTS (
        SELECT 1
        FROM Pelanggan
        WHERE id_pelanggan = p_id_pelanggan
          AND status_akun IN ('Ditangguhkan', 'Diblokir')
    ) THEN
        SET v_skor = v_skor + 25;
    END IF;

    -- Batas maksimum skor
    IF v_skor > 100 THEN
        SET v_skor = 100;
    END IF;

    RETURN v_skor;

END$$

DELIMITER ;

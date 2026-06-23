USE fp_rental_kendaraan;

DROP PROCEDURE IF EXISTS proc_proses_kendaraan_hilang;

DELIMITER $$

CREATE PROCEDURE proc_proses_kendaraan_hilang(
    IN p_kendaraan INT,
    IN p_keterangan TEXT
)

BEGIN

    DECLARE v_sewa INT DEFAULT NULL;
    DECLARE v_pelanggan INT DEFAULT NULL;
    DECLARE v_risiko INT DEFAULT 0;


    START TRANSACTION;


    SELECT 
        id_sewa,
        id_pelanggan

    FROM kontrak_sewa

    WHERE id_kendaraan = p_kendaraan
    AND status_sewa IN ('Aktif','Terlambat')

    ORDER BY tanggal_ambil DESC

    LIMIT 1

    INTO 
        v_sewa,
        v_pelanggan;



    UPDATE kendaraan

    SET status_kendaraan = 'Hilang'

    WHERE id_kendaraan = p_kendaraan;



    UPDATE kontrak_sewa

    SET status_sewa = 'Macet-Hukum'

    WHERE id_sewa = v_sewa;



    INSERT INTO log_anomali
    (
        id_sewa,
        jenis_anomali,
        waktu_log,
        deskripsi,
        skor_risiko,
        status_tindak_lanjut
    )

    SELECT
        v_sewa,
        'Kendaraan Hilang',
        CURRENT_TIMESTAMP,
        p_keterangan,
        50,
        'Prioritas Tinggi';



    SELECT fn_hitung_skor_risiko_pelanggan(v_pelanggan)

    INTO v_risiko;



    CASE

        WHEN v_risiko >= 90 THEN

            UPDATE pelanggan
            SET status_akun = 'Diblokir'
            WHERE id_pelanggan = v_pelanggan;


        WHEN v_risiko >= 70 THEN

            UPDATE pelanggan
            SET status_akun = 'Ditangguhkan'
            WHERE id_pelanggan = v_pelanggan;


        ELSE

            UPDATE pelanggan
            SET status_akun = 'Aktif'
            WHERE id_pelanggan = v_pelanggan;


    END CASE;


    COMMIT;


END$$

DELIMITER ;

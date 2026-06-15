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


    SELECT 
        COALESCE(SUM(la.skor_risiko),0)
    INTO v_skor
    FROM log_anomali la
    JOIN kontrak_sewa ks
        ON la.id_sewa = ks.id_sewa
    WHERE ks.id_pelanggan = p_id_pelanggan;


    SELECT 
        v_skor + (COUNT(*) * 50)
    INTO v_skor

    FROM kontrak_sewa ks

    JOIN kendaraan k
        ON ks.id_kendaraan = k.id_kendaraan

    WHERE ks.id_pelanggan = p_id_pelanggan

    AND k.status_kendaraan = 'Hilang';


    IF EXISTS (

        SELECT 1

        FROM pelanggan p

        JOIN daftar_hitam dh

        ON p.nik = dh.nik

        WHERE p.id_pelanggan = p_id_pelanggan

        AND dh.status_verifikasi='Terverifikasi'

    )

    THEN

        SET v_skor = v_skor + 50;

    END IF;


    IF v_skor > 100 THEN

        SET v_skor = 100;

    END IF;



    RETURN v_skor;


END$$


DELIMITER ;

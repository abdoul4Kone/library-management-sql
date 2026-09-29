-- On crée la base de données avec un encodage qui supporte les caractères spéciaux
CREATE DATABASE IF NOT EXISTS bibliotecho CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- On se positionne sur la base qu'on vient de créer
USE bibliotecho;

-- ****************************************************************************
-- ************************************TABLES**********************************
-- ****************************************************************************
-- table qui stocke les informations sur les auteurs des livres
-- un auteur peut avoir écrit plusieurs livres, et un livre peut avoir plusieurs auteurs
CREATE TABLE Auteur (
    IdAuteur INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique auto-généré
    Nom VARCHAR(50) NOT NULL,                -- Le nom de famille de l'auteur
    Prenom VARCHAR(50) NOT NULL,             -- Le prénom de l'auteur
    Nationalite VARCHAR(50) NOT NULL         -- La nationalité, utile pour les statistiques
) ENGINE=InnoDB;  -- On utilise InnoDB pour ses fonctionnalités transactionnelles

-- ****************************************************************************
-- table qui représente les livres dans notre catalogue
-- un livre peut avoir plusieurs exemplaires physiques (voir table Exemplaire)
CREATE TABLE Livre (
    ISBN VARCHAR(13) PRIMARY KEY,            -- Le code ISBN international, idéal comme clé primaire
    Titre VARCHAR(100) NOT NULL,             -- Le titre du livre (évidemment obligatoire!)
    AnneeEdition INT NOT NULL,               -- L'année d'édition pour savoir si c'est récent
    Editeur VARCHAR(50) NOT NULL,            -- La maison d'édition
    Genre VARCHAR(30) NOT NULL,              -- Le genre littéraire (roman, science, etc.)
    Valeur DECIMAL(10,2) NOT NULL,           -- Valeur monétaire du livre (pour les pénalités)
    DateAchat DATE NOT NULL,                 -- Quand on l'a acheté (pour calculer la dépréciation)
    NombreExemplairesTotal INT DEFAULT 0 NOT NULL,      -- Nb total d'exemplaires de ce livre
    NombreExemplairesDisponibles INT DEFAULT 0 NOT NULL -- Nb d'exemplaires disponibles
) ENGINE=InnoDB;

-- ****************************************************************************
-- cette table fait le lien entre les livres et les auteurs
CREATE TABLE LivreAuteur (
    ISBN VARCHAR(13) NOT NULL,       -- Référence au livre
    IdAuteur INT NOT NULL,           -- Référence à l'auteur
    PRIMARY KEY (ISBN, IdAuteur),    -- Clé primaire composée
    
    -- Si on supprime un livre, on supprime automatiquement ses liens avec les auteurs
    FOREIGN KEY (ISBN) REFERENCES Livre(ISBN) ON DELETE CASCADE,
    
    -- Si on supprime un auteur, on supprime automatiquement ses liens avec les livres
    FOREIGN KEY (IdAuteur) REFERENCES Auteur(IdAuteur) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ****************************************************************************
-- table pour les exemplaires physiques des livres
-- un même livre (ISBN) peut avoir plusieurs exemplaires (avec des codes différents)
CREATE TABLE Exemplaire (
    IdExemplaire INT AUTO_INCREMENT PRIMARY KEY,  -- Code unique pour chaque exemplaire
    ISBN VARCHAR(13) NOT NULL,                   -- Référence au livre correspondant
    Statut ENUM('Disponible', 'Emprunté', 'Réservé', 'Perdu') DEFAULT 'Disponible' NOT NULL,
    
    -- Si on supprime un livre, on supprime automatiquement tous ses exemplaires
    FOREIGN KEY (ISBN) REFERENCES Livre(ISBN) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ****************************************************************************
-- table qui contient les informations sur les membres de la bibliothèque
CREATE TABLE Adherent (
    IdAdherent INT AUTO_INCREMENT PRIMARY KEY,  -- Numéro unique d'adhérent
    Nom VARCHAR(50) NOT NULL,                  -- Nom de famille
    Prenom VARCHAR(50) NOT NULL,               -- Prénom
    Adresse VARCHAR(100) NOT NULL,             -- Adresse postale (pour les relances)
    Telephone VARCHAR(20) NOT NULL,            -- Numéro de téléphone (important!)
    DateInscription DATE NOT NULL,             -- Quand il/elle a rejoint la bibliothèque
    AbonnementActif BOOLEAN DEFAULT FALSE NOT NULL  -- Est-ce que son abonnement est valide?
) ENGINE=InnoDB;

-- ****************************************************************************
-- gestion des abonnements des adhérents
-- un adhérent peut avoir plusieurs abonnements successifs dans le temps
CREATE TABLE Abonnement (
    IdAbonnement INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique de l'abonnement
    IdAdherent INT NOT NULL,                     -- Référence à l'adhérent
    DateDebut DATE NOT NULL,                     -- Date de début de validité
    DateFin DATE NOT NULL,                       -- Date de fin de validité
    Montant DECIMAL(10,2) DEFAULT 5000.00 NOT NULL,  -- Montant (5000 FCFA par défaut)
    Statut ENUM('Actif', 'Expiré') DEFAULT 'Actif' NOT NULL,  -- Est-il encore valable?
    
    -- Si on supprime un adhérent, on supprime automatiquement ses abonnements
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ****************************************************************************
-- cette table enregistre tous les emprunts de livres par les adhérents
CREATE TABLE Emprunt (
    IdEmprunt INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique de l'emprunt
    IdAdherent INT NOT NULL,                   -- Qui a emprunté?
    IdExemplaire INT NOT NULL,                 -- Quel exemplaire précisément?
    DateDebut DATE NOT NULL,                   -- Date du début de l'emprunt
    DateRetourPrevue DATE NOT NULL,            -- Date à laquelle il devrait être rendu
    DateRetourEffective DATE,                  -- Date réelle de retour (NULL si pas encore rendu)
    Penalite DECIMAL(10,2) DEFAULT 0.00,       -- Montant de la pénalité si retard
    
    -- Contrôle d'intégrité référentielle
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent),
    FOREIGN KEY (IdExemplaire) REFERENCES Exemplaire(IdExemplaire)
) ENGINE=InnoDB;

-- ****************************************************************************
-- table qui gère les réservations de livres 
CREATE TABLE Reservation (
    IdReservation INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique
    IdAdherent INT NOT NULL,                      -- Qui réserve?
    ISBN VARCHAR(13) NOT NULL,                    -- Quel livre (pas d'exemplaire spécifique)
    DateReservation DATE NOT NULL,                -- Quand la réservation a été faite
    DateLimiteRecuperation DATE NOT NULL,         -- Date limite pour venir chercher le livre
    Statut ENUM('En Attente', 'Notifiée', 'Expirée', 'Terminée') DEFAULT 'En Attente' NOT NULL,
    
    -- Contrôle d'intégrité référentielle
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent),
    FOREIGN KEY (ISBN) REFERENCES Livre(ISBN)
) ENGINE=InnoDB;

-- ****************************************************************************
-- Cette table enregistre les pénalités pour retard ou livre perdu
CREATE TABLE Penalite (
    IdPenalite INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique
    IdAdherent INT NOT NULL,                    -- Qui doit payer?
    IdEmprunt INT NOT NULL,                     -- Pour quel emprunt?
    Montant DECIMAL(10,2) NOT NULL,             -- Combien doit-il?
    DatePenalite DATE NOT NULL,                 -- Date de la pénalité
    Statut ENUM('En Attente', 'Payée') DEFAULT 'En Attente' NOT NULL,  -- Est-ce payé?
    
    -- Contrôle d'intégrité référentielle
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent),
    FOREIGN KEY (IdEmprunt) REFERENCES Emprunt(IdEmprunt)
) ENGINE=InnoDB;

-- ****************************************************************************
-- ***********************************QUESTIONS******************************
-- ****************************************************************************

-- ****************************************************************************
-- QUESTION 1 : Triggers pour mise à jour du nombre d'exemplaires
-- "Mettre en place un trigger qui met à jour le nombre total de livre à chaque 
-- ajout ou suppression d'un exemplaire."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER ajout_question_1
AFTER INSERT ON Exemplaire
FOR EACH ROW
BEGIN
    /* Ce trigger s'active après chaque ajout d'un nouvel exemplaire
       et met à jour les compteurs dans la table Livre */
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal + 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles + 1
    WHERE ISBN = NEW.ISBN;
END //

CREATE TRIGGER supprime_question_1
AFTER DELETE ON Exemplaire
FOR EACH ROW
BEGIN
    /* Ce trigger s'active après suppression d'un exemplaire
       et ajuste les compteurs en fonction du statut de l'exemplaire supprimé */
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - CASE WHEN OLD.Statut = 'Perdu' THEN 0 ELSE 1 END,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles - 
            CASE WHEN OLD.Statut = 'Disponible' THEN 1 ELSE 0 END
    WHERE ISBN = OLD.ISBN;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 2 : Triggers pour gestion des disponibilités
-- "Mettre en place un trigger qui met à jour le nombre d'exemplaires 
-- disponibles à chaque emprunt et retour"
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER ajout_question_2
AFTER INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Lors d'un nouvel emprunt :
       1. Met à jour le statut de l'exemplaire à "Emprunté"
       2. Décrémente le compteur d'exemplaires disponibles */
    UPDATE Exemplaire SET Statut = 'Emprunté' WHERE IdExemplaire = NEW.IdExemplaire;
    UPDATE Livre l JOIN Exemplaire e ON l.ISBN = e.ISBN
    SET l.NombreExemplairesDisponibles = l.NombreExemplairesDisponibles - 1
    WHERE e.IdExemplaire = NEW.IdExemplaire;
END //

CREATE TRIGGER supprime_question_2
AFTER UPDATE ON Emprunt
FOR EACH ROW
BEGIN
    /* Lors du retour d'un livre (date effective renseignée) :
       1. Remet le statut à "Disponible"
       2. Incrémente le compteur d'exemplaires disponibles */
    IF NEW.DateRetourEffective IS NOT NULL AND OLD.DateRetourEffective IS NULL THEN
        UPDATE Exemplaire SET Statut = 'Disponible' WHERE IdExemplaire = NEW.IdExemplaire;
        UPDATE Livre l JOIN Exemplaire e ON l.ISBN = e.ISBN
        SET l.NombreExemplairesDisponibles = l.NombreExemplairesDisponibles + 1
        WHERE e.IdExemplaire = NEW.IdExemplaire;
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 3 : Trigger pour limite d'emprunts
-- "Mettre en place un trigger qui vérifie que le nombre de livre emprunté par 
-- un adhérent n'excède pas 3 avant la validation de l'emprunt."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER limite_emprunts_question_3
BEFORE INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Empêche un adhérent d'avoir plus de 3 emprunts simultanés */
    DECLARE nb_emprunts INT;
    DECLARE abonnement_actif INT;
    DECLARE exemplaire_disponible INT;

    SELECT COUNT(*) INTO abonnement_actif
    FROM Abonnement
    WHERE IdAdherent = NEW.IdAdherent
      AND Statut = 'Actif'
      AND CURDATE() BETWEEN DateDebut AND DateFin;

    IF abonnement_actif = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un abonnement actif est requis pour emprunter';
    END IF;

    IF NEW.DateRetourPrevue < NEW.DateDebut
       OR NEW.DateRetourPrevue > DATE_ADD(NEW.DateDebut, INTERVAL 15 DAY) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La durée d''un emprunt ne peut pas dépasser 15 jours';
    END IF;

    SELECT COUNT(*) INTO exemplaire_disponible
    FROM Exemplaire
    WHERE IdExemplaire = NEW.IdExemplaire AND Statut = 'Disponible';

    IF exemplaire_disponible = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cet exemplaire n''est pas disponible';
    END IF;
    
    SELECT COUNT(*) INTO nb_emprunts 
    FROM Emprunt 
    WHERE IdAdherent = NEW.IdAdherent AND DateRetourEffective IS NULL;
    
    IF nb_emprunts >= 3 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Limite de 3 emprunts atteinte pour cet adhérent';
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 4 : Trigger pour exemplaire unique
-- "Mettre en place un trigger qui vérifie qu'un adhérent n'est pas en train 
-- d'emprunter plus d'un exemplaire d'un livre donné avant validation de l'emprunt."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER unique_question_4
BEFORE INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Empêche un adhérent d'emprunter plusieurs exemplaires du même livre */
    DECLARE nb_emprunts_meme_livre INT;
    
    SELECT COUNT(*) INTO nb_emprunts_meme_livre
    FROM Emprunt e
    JOIN Exemplaire ex ON e.IdExemplaire = ex.IdExemplaire
    JOIN Exemplaire new_ex ON ex.ISBN = new_ex.ISBN
    WHERE e.IdAdherent = NEW.IdAdherent 
    AND e.DateRetourEffective IS NULL
    AND new_ex.IdExemplaire = NEW.IdExemplaire;
    
    IF nb_emprunts_meme_livre > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Adhérent a déjà un exemplaire de ce livre en cours d''emprunt';
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 5 : Trigger pour pénalités impayées
-- "Mettre en place un trigger qui vérifie qu'un adhérent n'a pas de pénalités 
-- non payées avant validation d'un emprunt."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER penalites_impayees_question_5
BEFORE INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Bloque l'emprunt si l'adhérent a des pénalités non réglées */
    DECLARE penalites_impayees INT;
    
    SELECT COUNT(*) INTO penalites_impayees
    FROM Penalite
    WHERE IdAdherent = NEW.IdAdherent AND Statut = 'En Attente';
    
    IF penalites_impayees > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Adhérent a des pénalités impayées';
    END IF;
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER verifier_reservation
BEFORE INSERT ON Reservation
FOR EACH ROW
BEGIN
    DECLARE abonnement_actif INT;
    DECLARE exemplaires_existants INT;
    DECLARE nb_emprunts INT;
    DECLARE nb_reservations INT;
    DECLARE limite_reservations INT;

    SELECT COUNT(*) INTO abonnement_actif
    FROM Abonnement
    WHERE IdAdherent = NEW.IdAdherent
      AND Statut = 'Actif'
      AND CURDATE() BETWEEN DateDebut AND DateFin;

    IF abonnement_actif = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un abonnement actif est requis pour réserver';
    END IF;

    SELECT COUNT(*) INTO exemplaires_existants
    FROM Exemplaire
    WHERE ISBN = NEW.ISBN AND Statut <> 'Perdu';

    IF exemplaires_existants = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ce livre ne possède aucun exemplaire';
    END IF;

    SELECT COUNT(*) INTO nb_emprunts
    FROM Emprunt
    WHERE IdAdherent = NEW.IdAdherent AND DateRetourEffective IS NULL;

    SELECT COUNT(*) INTO nb_reservations
    FROM Reservation
    WHERE IdAdherent = NEW.IdAdherent
      AND Statut IN ('En Attente', 'Notifiée');

    SET limite_reservations = IF(nb_emprunts >= 3, 1, 2);
    IF nb_reservations >= limite_reservations THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Limite de réservations atteinte pour cet adhérent';
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 6 : Transaction pour exemplaire égaré
-- "Mettre en place une transaction permettant de supprimer un exemplaire
-- égaré par un adhérent."
-- ****************************************************************************

DELIMITER //
CREATE PROCEDURE supprimer_exemplaire_egare(
    IN p_id_exemplaire INT,
    IN p_id_adherent INT
)
BEGIN
    /* La copie reste dans le catalogue afin de préserver l'historique d'emprunt. */
    DECLARE v_isbn VARCHAR(13);
    DECLARE v_valeur DECIMAL(10,2);
    DECLARE v_id_emprunt INT DEFAULT NULL;
    DECLARE v_statut VARCHAR(20);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- La perte doit correspondre à un emprunt actif de cet adhérent.
    SELECT em.IdEmprunt, ex.ISBN, l.Valeur, ex.Statut
    INTO v_id_emprunt, v_isbn, v_valeur, v_statut
    FROM Emprunt em
    JOIN Exemplaire ex ON ex.IdExemplaire = em.IdExemplaire
    JOIN Livre l ON ex.ISBN = l.ISBN
    WHERE em.IdExemplaire = p_id_exemplaire
      AND em.IdAdherent = p_id_adherent
      AND em.DateRetourEffective IS NULL
    FOR UPDATE;

    IF v_id_emprunt IS NULL OR v_statut <> 'Emprunté' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Aucun emprunt actif de cet exemplaire pour cet adhérent';
    END IF;
    
    -- Enregistrer la pénalité (valeur du livre)
    INSERT INTO Penalite (IdAdherent, IdEmprunt, Montant, DatePenalite, Statut)
    VALUES (p_id_adherent, v_id_emprunt, v_valeur, CURDATE(), 'En Attente');
    
    -- Clôturer l'emprunt et conserver la copie pour préserver l'historique.
    UPDATE Emprunt
    SET DateRetourEffective = CURDATE(), Penalite = v_valeur
    WHERE IdEmprunt = v_id_emprunt;

    UPDATE Exemplaire
    SET Statut = 'Perdu'
    WHERE IdExemplaire = p_id_exemplaire;
    
    -- Le déclencheur de retour a rendu la copie disponible juste avant sa perte.
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles - 1
    WHERE ISBN = v_isbn;
    
    COMMIT;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 7 : Transaction pour retour de livre
-- "Ecrire une transaction pour enregistrer les retours de livre. Cette
-- transaction évalue s'il y a des pénalités à appliquées et les enregistres."
-- ****************************************************************************

DELIMITER //
CREATE PROCEDURE enregistrer_retour(
    IN p_id_emprunt INT,
    IN p_date_retour DATE
)
BEGIN
    /* Procédure transactionnelle pour :
       1. Enregistrer la date de retour effective
       2. Calculer les pénalités si retard
       3. Mettre à jour les données */
    DECLARE v_retard INT;
    DECLARE v_id_adherent INT;
    DECLARE v_penalite DECIMAL(10,2);
    DECLARE v_date_debut DATE;
    DECLARE v_date_retour_effective DATE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Calculer le retard en jours (500 FCFA par jour)
    SELECT DATEDIFF(p_date_retour, DateRetourPrevue), IdAdherent,
           DateDebut, DateRetourEffective
    INTO v_retard, v_id_adherent, v_date_debut, v_date_retour_effective
    FROM Emprunt
    WHERE IdEmprunt = p_id_emprunt
    FOR UPDATE;

    IF v_retard IS NULL OR v_date_retour_effective IS NOT NULL
       OR p_date_retour < v_date_debut THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Emprunt introuvable, déjà clôturé ou date de retour invalide';
    END IF;
    
    -- Mettre à jour l'emprunt
    UPDATE Emprunt 
    SET DateRetourEffective = p_date_retour,
        Penalite = CASE WHEN v_retard > 0 THEN v_retard * 500 ELSE 0 END
    WHERE IdEmprunt = p_id_emprunt;
    
    -- Si retard, enregistrer la pénalité
    IF v_retard > 0 THEN
        SET v_penalite = v_retard * 500;
        
        INSERT INTO Penalite (IdAdherent, IdEmprunt, Montant, DatePenalite, Statut)
        VALUES (v_id_adherent, p_id_emprunt, v_penalite, CURDATE(), 'En Attente');
    END IF;
    
    COMMIT;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 8 : Paiement de pénalité
-- "Ecrire une requête SQL permettant d'enregistrer le paiement d'une pénalité."
-- ****************************************************************************

SET @id_penalite = NULL; -- Renseigner l'identifiant avant d'exécuter la requête
UPDATE Penalite
SET Statut = 'Payée'
WHERE IdPenalite = @id_penalite;

-- ****************************************************************************
-- QUESTION 9 : Désactivation abonnements expirés
-- "Ecrire une requête SQL permettant de désactiver tous les abonnements
-- arrivés à expiration."
-- ****************************************************************************

-- Désactive les abonnements expirés
UPDATE Abonnement
SET Statut = 'Expiré'
WHERE DateFin < CURDATE() AND Statut = 'Actif';

-- Met à jour le statut des adhérents concernés
UPDATE Adherent a
SET a.AbonnementActif = EXISTS (
        SELECT 1
        FROM Abonnement ab
        WHERE ab.IdAdherent = a.IdAdherent
            AND ab.Statut = 'Actif'
            AND CURDATE() BETWEEN ab.DateDebut AND ab.DateFin
);

-- ****************************************************************************
-- QUESTION 10 : Mise à jour réservations
-- "Ecrire une requête SQL permettant de mettre à jour les réservations."
-- ****************************************************************************

-- Marque les réservations expirées (non récupérées dans les 3 jours)
UPDATE Reservation
SET Statut = 'Expirée'
WHERE DateLimiteRecuperation < CURDATE() AND Statut = 'Notifiée';

-- Notifie la prochaine réservation en attente quand un exemplaire est disponible
UPDATE Reservation r
JOIN (
    SELECT IdReservation
    FROM (
        SELECT IdReservation,
               ROW_NUMBER() OVER (PARTITION BY ISBN ORDER BY DateReservation, IdReservation) AS rang_file
        FROM Reservation
        WHERE Statut = 'En Attente'
    ) AS reservations_classees
    WHERE rang_file = 1
) AS prochaine ON prochaine.IdReservation = r.IdReservation
JOIN Livre l ON r.ISBN = l.ISBN
SET r.Statut = 'Notifiée',
    r.DateLimiteRecuperation = DATE_ADD(CURDATE(), INTERVAL 3 DAY)
WHERE l.NombreExemplairesDisponibles > 0
  AND r.Statut = 'En Attente';

-- ****************************************************************************
-- QUESTION 11 : Transaction pour réservations expirées
-- "Ecrire une transaction qui supprime toutes les réservations arrivées à
-- expiration (3 jours sans réaction de l'adhérent) puis met à jour les
-- réservations en attente par ordre de priorité en fonction des disponibilités."
-- ****************************************************************************

DELIMITER //
CREATE PROCEDURE traiter_reservations_expirees()
BEGIN
    /* Procédure transactionnelle pour :
       1. Supprimer les réservations expirées
       2. Notifier les suivants dans la file d'attente */
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_isbn VARCHAR(13);
    DECLARE cur CURSOR FOR
        SELECT DISTINCT ISBN
        FROM Reservation
        WHERE Statut = 'Notifiée' AND DateLimiteRecuperation < CURDATE();
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Capturer et traiter la file avant de supprimer les réservations expirées.
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_isbn;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        UPDATE Reservation
        SET Statut = 'Expirée'
        WHERE ISBN = v_isbn
          AND Statut = 'Notifiée'
          AND DateLimiteRecuperation < CURDATE();

        IF EXISTS (
            SELECT 1 FROM Livre
            WHERE ISBN = v_isbn AND NombreExemplairesDisponibles > 0
        ) THEN
            UPDATE Reservation
            SET Statut = 'Notifiée',
                DateLimiteRecuperation = DATE_ADD(CURDATE(), INTERVAL 3 DAY)
            WHERE ISBN = v_isbn
              AND Statut = 'En Attente'
              AND IdReservation = (
                  SELECT prochaine.IdReservation
                  FROM (
                      SELECT r.IdReservation
                      FROM Reservation r
                      WHERE r.ISBN = v_isbn AND r.Statut = 'En Attente'
                      ORDER BY r.DateReservation, r.IdReservation
                      LIMIT 1
                  ) AS prochaine
              );
        END IF;
    END LOOP;
    CLOSE cur;

    DELETE FROM Reservation
    WHERE Statut = 'Expirée' AND DateLimiteRecuperation < CURDATE();
    
    COMMIT;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 12 : Enregistrement d'occurences
-- " Enregistrer au moins 5 occurrences de livres, d’emprunts, de réservations, 
--  de retours de livre, de suppression de livres avec 2 livres égarés par des 
--  adhérents pour vérifier la bonne marche de votre base de données
-- ****************************************************************************

-- Insertion d'auteurs
INSERT INTO Auteur (Nom, Prenom, Nationalite) VALUES
('Hugo', 'Victor', 'Française'),
('Orwell', 'George', 'Britannique'),
('Asimov', 'Isaac', 'Américaine'),
('Rowling', 'J.K.', 'Britannique'),
('Christie', 'Agatha', 'Britannique');

-- Insertion de livres
INSERT INTO Livre (ISBN, Titre, AnneeEdition, Editeur, Genre, Valeur, DateAchat, NombreExemplairesTotal, NombreExemplairesDisponibles) VALUES
('9782070360028', 'Les Misérables', 1862, 'Gallimard', 'Roman', 25.00, '2023-01-15', 0, 0),
('9782070360530', '1984', 1949, 'Gallimard', 'Science-Fiction', 20.00, '2023-02-20', 0, 0),
('9782290032726', 'Fondation', 1951, 'J''ai lu', 'Science-Fiction', 18.00, '2023-03-10', 0, 0),
('9782070584621', 'Harry Potter à l''école des sorciers', 1997, 'Gallimard', 'Fantasy', 22.00, '2023-04-05', 0, 0),
('9782253004247', 'Le Crime de l''Orient-Express', 1934, 'Le Livre de Poche', 'Policier', 15.00, '2023-05-12', 0, 0);

-- Insertion de relations Livre-Auteur
INSERT INTO LivreAuteur (ISBN, IdAuteur) VALUES
('9782070360028', 1),
('9782070360530', 2),
('9782290032726', 3),
('9782070584621', 4),
('9782253004247', 5);

-- Insertion d'exemplaires
INSERT INTO Exemplaire (ISBN, Statut) VALUES
('9782070360028', 'Disponible'),
('9782070360028', 'Disponible'),
('9782070360028', 'Disponible'),
('9782070360530', 'Disponible'),
('9782070360530', 'Disponible'),
('9782290032726', 'Disponible'),
('9782290032726', 'Disponible'),
('9782070584621', 'Disponible'),
('9782070584621', 'Disponible'),
('9782070584621', 'Disponible'),
('9782070584621', 'Disponible'),
('9782253004247', 'Disponible'),
('9782253004247', 'Disponible');

-- Insertion d'adhérents
INSERT INTO Adherent (Nom, Prenom, Adresse, Telephone, DateInscription, AbonnementActif) VALUES
('Membre', 'Test 1', 'Adresse fictive 1', '0000000001', '2023-01-10', TRUE),
('Membre', 'Test 2', 'Adresse fictive 2', '0000000002', '2023-02-15', TRUE),
('Membre', 'Test 3', 'Adresse fictive 3', '0000000003', '2023-03-20', TRUE),
('Membre', 'Test 4', 'Adresse fictive 4', '0000000004', '2023-04-25', TRUE),
('Membre', 'Test 5', 'Adresse fictive 5', '0000000005', '2023-05-30', TRUE);

-- Insertion d'abonnements
INSERT INTO Abonnement (IdAdherent, DateDebut, DateFin, Montant, Statut) VALUES
(1, STR_TO_DATE(DATE_FORMAT(CURDATE(), '%Y-%m-01'), '%Y-%m-%d'), LAST_DAY(CURDATE()), 5000.00, 'Actif'),
(2, STR_TO_DATE(DATE_FORMAT(CURDATE(), '%Y-%m-01'), '%Y-%m-%d'), LAST_DAY(CURDATE()), 5000.00, 'Actif'),
(3, STR_TO_DATE(DATE_FORMAT(CURDATE(), '%Y-%m-01'), '%Y-%m-%d'), LAST_DAY(CURDATE()), 5000.00, 'Actif'),
(4, STR_TO_DATE(DATE_FORMAT(CURDATE(), '%Y-%m-01'), '%Y-%m-%d'), LAST_DAY(CURDATE()), 5000.00, 'Actif'),
(5, STR_TO_DATE(DATE_FORMAT(CURDATE(), '%Y-%m-01'), '%Y-%m-%d'), LAST_DAY(CURDATE()), 5000.00, 'Actif');

-- Insertion d'emprunts
INSERT INTO Emprunt (IdAdherent, IdExemplaire, DateDebut, DateRetourPrevue) VALUES
(1, 1, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY)),
(1, 4, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY)),
(2, 6, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY)),
(3, 8, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY)),
(5, 11, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY)),
(2, 2, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY)),
(3, 12, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY));

-- Insertion de réservations
INSERT INTO Reservation (IdAdherent, ISBN, DateReservation, DateLimiteRecuperation, Statut) VALUES
(1, '9782070360028', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(2, '9782070360028', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(3, '9782070584621', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(4, '9782253004247', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(5, '9782070360530', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(1, '9782290032726', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente');

-- Enregistrement de retours avec pénalités
CALL enregistrer_retour(1, DATE_SUB(CURDATE(), INTERVAL 3 DAY)); -- 2 jours de retard
CALL enregistrer_retour(2, DATE_SUB(CURDATE(), INTERVAL 3 DAY)); -- 2 jours de retard
CALL enregistrer_retour(3, DATE_SUB(CURDATE(), INTERVAL 5 DAY));
CALL enregistrer_retour(4, DATE_SUB(CURDATE(), INTERVAL 5 DAY));
CALL enregistrer_retour(5, DATE_SUB(CURDATE(), INTERVAL 5 DAY));

UPDATE Reservation
SET Statut = 'Notifiée', DateLimiteRecuperation = DATE_SUB(CURDATE(), INTERVAL 4 DAY)
WHERE IdReservation = 1;
CALL traiter_reservations_expirees();

CALL supprimer_exemplaire_egare(2, 2);
CALL supprimer_exemplaire_egare(12, 3);



-- ****************************************************************************
-- QUESTION 13 : Requête livres scientifiques par adhérent
-- "Ecrire une requête SQL permettant d'afficher tous les livres du genre
-- science commandés par chaque adhérent."
-- ****************************************************************************

SELECT 
    a.IdAdherent,
    CONCAT(a.Nom, ' ', a.Prenom) AS Adherent,
    l.Titre,
    l.Genre,
    COUNT(e.IdEmprunt) AS NombreEmprunts
FROM 
    Adherent a
JOIN 
    Emprunt e ON a.IdAdherent = e.IdAdherent
JOIN 
    Exemplaire ex ON e.IdExemplaire = ex.IdExemplaire
JOIN 
    Livre l ON ex.ISBN = l.ISBN
WHERE 
    l.Genre = 'Science-Fiction' -- Adaptez selon les genres dans votre base
GROUP BY 
    a.IdAdherent, l.Titre, l.Genre
ORDER BY 
    a.Nom, a.Prenom, NombreEmprunts DESC;



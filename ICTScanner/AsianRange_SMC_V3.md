
Voici votre **Guide Utilisateur** pour le Master Scanner Asian Range (V1.10) :

### 1. Rôle de l'EA
Cet Expert Advisor est un **radar automatique**. Il surveille l'ensemble des actifs de votre fenêtre "Observation du marché" (Market Watch) et vous alerte dès que le prix s'approche des zones de liquidité créées durant la session asiatique.

### 2. Configuration des Paramètres (Inputs)
*   **StartHour (0) & EndHour (8) :** Définit la plage horaire de la session asiatique (Heure du Broker). L'EA calculera le plus haut et le plus bas entre ces deux bornes.
*   **AlertDistancePoints (50) :** Définit la sensibilité. Si réglé sur 50, vous recevrez l'alerte quand le prix est à moins de 5 pips (Forex) ou 0.50 points (Or) de la zone.

### 3. Fonctionnement du Scanner
*   **Fréquence :** L'EA scanne tous vos actifs toutes les **30 secondes**.
*   **Intelligence :** Il n'envoie **qu'une seule alerte** par côté (Haut ou Bas) par jour et par actif pour éviter de vous spammer.
*   **Reset :** La mémoire de l'EA se réinitialise automatiquement chaque jour à **minuit**.

### 4. Réception des Alertes
Dès qu'une zone est approchée, l'EA génère une alerte contenant :
1.  **Le nom de l'actif** concerné.
2.  **Le type de zone** (Asian High ou Asian Low).
3.  **Le prix actuel** du marché.
4.  **Le niveau exact** de la liquidité à surveiller.

*Note : Si votre MT5 est configuré avec votre ID MetaQuotes, vous recevrez également ces alertes sur votre smartphone.*

### 5. Conseils d'utilisation
*   **Installation unique :** Ne déposez cet EA que sur **un seul graphique** (n'importe lequel). Il s'occupe de tous les autres actifs en arrière-plan.
*   **Contrôle du scan :** Pour arrêter de surveiller un actif, retirez-le simplement de votre fenêtre "Observation du marché".
*   **Visualisation :** Pour voir les zones sur votre graphique, utilisez l'indicateur visuel complémentaire (placé dans votre `default.tpl`).

**Objectif :** Vous permettre de ne plus rater aucun "sweep" de liquidité, même sur des actifs que vous ne regardez pas activement.

**Scanner pur (Assistant de Trading)** : le robot est le "chien de chasse" qui rabat le gibier, et vous êtes le "chasseur" qui décide de tirer ou non.

Voici la procédure étape par étape pour l'utiliser efficacement :

### 1. La Configuration (Mise en place)
*   **Remplissez votre Market Watch :** Ajoutez tous les actifs que vous voulez surveiller (Forex, Indices, Or, Crypto). Le robot va tout scanner.
*   **Lancez le Scanner :** Glissez le robot sur **un seul graphique** (n'importe lequel, par exemple EURUSD M1). Il travaillera en arrière-plan pour toute la liste.
*   **Attendez :** Ne faites rien. Laissez le robot tourner.

### 2. Réception de l'Alerte
Supposons que vous receviez cette alerte (Telegram ou Pop-up) :
> **SCANNER: GBPJPY | BUY POTENTIAL**
> **Patterns: [OrderBlock]**
> **Zone Price: 184.500**

Cela signifie : "La tendance de fond (H1) est haussière, et le prix vient de redescendre pour toucher un Order Block (M15) autour des 184.500".

### 3. Votre Analyse (Le filtre humain)
C'est là que vous intervenez. Le code est mathématique et peut se tromper de contexte.
1.  **Ouvrez le graphique** du GBPJPY.
2.  **Mettez-vous en M15** (le timeframe du pattern).
3.  **Identifiez visuellement la zone :** Cherchez la dernière bougie rouge avant la montée impulsive récente. C'est l'Order Block que le robot a vu.
4.  **Validez le contexte :**
    *   Est-ce que la tendance H1 est *vraiment* propre à l'œil nu ?
    *   Y a-t-il une annonce économique (News) imminente ? (Le robot ne le sait pas).
    *   L'Order Block a-t-il l'air solide (grosse impulsion après) ?

### 4. La Prise de Position (L'exécution)
Si le contexte vous plaît :
1.  **Descendez en M5** (Microstructure).
2.  **Attendez une réaction :** Ne placez pas un ordre "Limit" aveugle. Attendez de voir le prix ralentir dans la zone ou faire une bougie de rejet (mèche) ou une englobante.
3.  **Placez votre ordre manuellement :**
    *   **Achat (Buy) :** Au marché.
    *   **Stop Loss (SL) :** Placez-le sous le plus bas de l'Order Block M15 ou sous le dernier creux M5.
    *   **Take Profit (TP) :** Visez le prochain sommet (High) ou un ratio Risque/Rendement de 1:2 ou 1:3.

### Résumé du Workflow

| Qui fait quoi ? | Action |
| :--- | :--- |
| **Le Robot** | Scanne 20+ actifs 24/7. Vérifie la tendance H1. Trouve les zones M15. |
| **Le Robot** | **DING !** Vous envoie une alerte "Opportunité sur l'OR (XAUUSD)". |
| **Vous** | Ouvrez le graphique. Jugez la qualité de la zone. Vérifiez les News. |
| **Vous** | Décidez d'entrer ou d'ignorer. Placez le SL et le TP. |

### Conseil Pro
N'acceptez pas tous les signaux aveuglément. Ce code utilise une définition *mécanique* des concepts ICT (basée sur des bougies 1, 2, 3...). Le véritable trading SMC/ICT demande de regarder la "liquidité" (les stops des autres traders).
Utilisez ce scanner pour **gagner du temps** (ne pas regarder l'écran quand il ne se passe rien), mais gardez votre jugement critique pour l'entrée.

//+------------------------------------------------------------------+
//|                                               Gold_Long_EA.mq5  |
//|                                  Auto Trade sur clôture bougie  |
//|                                          Version corrigée v2.0  |
//|                                                    Version LONG |
//|                                                      + SL + Alert|
//+------------------------------------------------------------------+
#property copyright "Gold EA"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Paramètres d'entrée modifiables dans l'EA                        |
//+------------------------------------------------------------------+
input double   Niveau_Declenchement = 4635.83;  // Prix de déclenchement (clôture bougie >)
input double   TakeProfit           = 4645;     // Take Profit (au-dessus du prix d'entrée)
input double   StopLoss             = 0;        // Stop Loss (0 = auto basé sur TP avec ratio 1:2)
input double   RatioSL_TP           = 2.0;      // Ratio TP/SL (si SL=0, TP = SL x Ratio) -> ici TP 2x plus large que SL
input double   Lots                 = 0.35;     // Volume des lots
input int      MagicNumber          = 202411;   // Identifiant unique du trade
input int      Slippage             = 50;       // Slippage maximum en points

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
bool trade_effectue = false;
datetime derniere_bougie_fermee = 0;
bool alerteAutoTradeEnvoyee = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade_effectue = false;
    derniere_bougie_fermee = 0;
    alerteAutoTradeEnvoyee = false;
    
    Print("═══════════════════════════════════════════════════════");
    Print("⭐ EA GOLD LONG - INITIALISÉ ⭐");
    Print("═══════════════════════════════════════════════════════");
    Print("📊 Symbole : ", _Symbol);
    Print("⏱️ Timeframe : M5");
    Print("🎯 Niveau déclenchement (au-dessus) : ", Niveau_Declenchement);
    Print("💰 Take Profit : ", TakeProfit);
    
    // Affichage du SL avec calcul simulé (basé sur prix actuel approximatif)
    if(StopLoss == 0)
    {
        double prix_actuel_simule = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double distance_tp_simulee = TakeProfit - prix_actuel_simule;
        
        if(distance_tp_simulee > 0)
        {
            double distance_sl_simulee = distance_tp_simulee / RatioSL_TP;
            double sl_simule = prix_actuel_simule - distance_sl_simulee;
            
            Print("🛑 Stop Loss   : AUTO (calculé selon ratio 1:", RatioSL_TP, ")");
            Print("   📐 Exemple avec prix actuel (", DoubleToString(prix_actuel_simule, _Digits), "):");
            Print("      → SL auto = ", DoubleToString(sl_simule, _Digits));
            Print("      → Distance TP: +", DoubleToString(distance_tp_simulee, _Digits));
            Print("      → Distance SL: -", DoubleToString(distance_sl_simulee, _Digits));
            Print("      → Ratio TP/SL = ", RatioSL_TP, ":1 (TP 2x plus large que SL)");
        }
        else
        {
            Print("🛑 Stop Loss   : AUTO (ATTENTION: TP en dessous du prix actuel!)");
        }
    }
    else
    {
        Print("🛑 Stop Loss   : ", StopLoss);
    }
    
    Print("📦 Volume : ", Lots, " lots");
    Print("═══════════════════════════════════════════════════════");
    
    // Afficher l'heure serveur pour référence
    Print("⏰ Heure serveur : ", TimeToString(TimeCurrent()));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("🔴 EA GOLD LONG - DÉSACTIVÉ (code: ", reason, ")");
}

//+------------------------------------------------------------------+
//| Vérifier si le trading automatique est activé                    |
//+------------------------------------------------------------------+
bool VerifierAutoTrade()
{
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        if(!alerteAutoTradeEnvoyee)
        {
            string msg = "⚠️ ALERTE: Le trading automatique n'est pas activé ! " +
                         "Veuillez cliquer sur le bouton 'AutoTrading' (vert) pour activer les trades.";
            Print(msg);
            Alert(msg);
            PlaySound("alert.wav");
            SendNotification("Gold Long EA: AutoTrading désactivé!");
            alerteAutoTradeEnvoyee = true;
        }
        return false;
    }
    
    alerteAutoTradeEnvoyee = false;
    return true;
}

//+------------------------------------------------------------------+
//| Expert tick function - VERSION CORRIGÉE POUR LONG                |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérifier si le trading auto est activé
    if(!VerifierAutoTrade())
    {
        return; // Trading auto désactivé, on attend
    }
    
    // 1. Vérifier si un trade est déjà ouvert
    if(CountTrades() > 0)
    {
        return; // Trade déjà ouvert, on ne fait rien
    }
    
    // 2. Récupérer l'heure de la dernière bougie COMPLÈTEMENT FERMÉE
    //    iTime(..., 1) = début de la bougie d'avant (celle qui est fermée)
    datetime debut_bougie_fermee = iTime(_Symbol, PERIOD_M5, 1);
    
    // 3. Si une nouvelle bougie vient de se fermer
    if(debut_bougie_fermee != derniere_bougie_fermee)
    {
        derniere_bougie_fermee = debut_bougie_fermee;
        
        // 4. Calculer l'heure RÉELLE de fermeture (début + 5 minutes)
        datetime heure_fermeture_reelle = debut_bougie_fermee + (5 * 60);
        
        // 5. Récupérer le prix de clôture (indice 1 = bougie fermée)
        double prix_fermeture = iClose(_Symbol, PERIOD_M5, 1);
        double prix_ouverture = iOpen(_Symbol, PERIOD_M5, 1);
        double prix_haut = iHigh(_Symbol, PERIOD_M5, 1);
        double prix_bas = iLow(_Symbol, PERIOD_M5, 1);
        
        // 6. Afficher les informations de la bougie fermée
        Print("───────────────────────────────────────────────────");
        Print("📌 NOUVELLE BOUGIE FERMÉE");
        Print("   🕐 Début    : ", TimeToString(debut_bougie_fermee));
        Print("   🕐 Fermeture: ", TimeToString(heure_fermeture_reelle));
        Print("   📈 Ouverture: ", prix_ouverture);
        Print("   📊 Clôture  : ", prix_fermeture);
        Print("   📈 Haut     : ", prix_haut);
        Print("   📉 Bas      : ", prix_bas);
        Print("───────────────────────────────────────────────────");
        
        // 7. Vérifier la condition de déclenchement pour LONG
        //    Condition: prix de clôture > niveau de déclenchement
        if(prix_fermeture > Niveau_Declenchement && !trade_effectue)
        {
            Print("🎯🎯🎯 CONDITION LONG VALIDÉE ! 🎯🎯🎯");
            Print("   Clôture (", prix_fermeture, ") > Seuil (", Niveau_Declenchement, ")");
            Print("   ▶️ Déclenchement du trade LONG...");
            
            PrendreTradeLong();
            trade_effectue = true;
        }
        else
        {
            if(prix_fermeture <= Niveau_Declenchement)
            {
                double ecart = Niveau_Declenchement - prix_fermeture;
                Print("⏳ Condition LONG NON remplie (encore ", DoubleToString(ecart, 2), " points manquants)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Fonction pour prendre un trade LONG (MARKET ORDER)               |
//+------------------------------------------------------------------+
void PrendreTradeLong()
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    // Vérifier la marge disponible
    double marge_libre = AccountInfoDouble(ACCOUNT_FREEMARGIN);
    double marge_requise = Lots * 1000; // Estimation approximative
    
    if(marge_libre < marge_requise)
    {
        Print("❌ ERREUR: Marge insuffisante!");
        Print("   Marge libre: ", DoubleToString(marge_libre, 2));
        Print("   Marge requise estimée: ", DoubleToString(marge_requise, 2));
        return;
    }
    
    // Récupérer le prix actuel (Ask pour un LONG)
    double prix_actuel = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Calcul du Stop Loss (auto si = 0)
    double sl_final = StopLoss;
    double tp = TakeProfit;
    
    if(sl_final == 0)
    {
        // Pour un LONG : TP est plus HAUT que l'entrée
        // Distance TP = TP - entrée
        double distance_tp = tp - prix_actuel;
        
        // Vérifier que le TP est bien au-dessus (distance positive)
        if(distance_tp <= 0)
        {
            Print("❌ ERREUR: Take Profit (", tp, ") n'est pas au-dessus du prix d'entrée (", prix_actuel, ")");
            Print("   Le TP doit être supérieur au prix d'entrée pour un LONG!");
            return;
        }
        
        // Rapport 1:2 = TP est 2x plus large que SL
        // Donc SL = TP / 2
        double distance_sl = distance_tp / RatioSL_TP;
        sl_final = prix_actuel - distance_sl;
        
        Print("🔧 SL auto-calculé (TP ", RatioSL_TP, "x plus large que SL)");
        Print("   Entrée: ", prix_actuel);
        Print("   TP: ", tp, " (distance: +", distance_tp, " pts)");
        Print("   SL auto: ", sl_final, " (distance: -", distance_sl, " pts)");
        Print("   Ratio réel TP/SL: ", distance_tp/distance_sl, ":1");
    }
    else
    {
        Print("🔧 SL manuel utilisé: ", sl_final);
    }
    
    // Configuration de la requête
    request.action      = TRADE_ACTION_DEAL;     // Action immédiate (market order)
    request.symbol      = _Symbol;               // Symbole (XAUUSD)
    request.volume      = Lots;                  // Volume en lots
    request.type        = ORDER_TYPE_BUY;        // Ordre d'achat LONG
    request.price       = prix_actuel;           // Prix actuel du marché
    request.deviation   = Slippage;              // Slippage maximum autorisé
    request.magic       = MagicNumber;           // Identifiant du trade
    request.type_filling = ORDER_FILLING_FOK;    // Type d'exécution (Fill or Kill)
    request.tp          = tp;                    // Take Profit (au-dessus)
    request.sl          = sl_final;              // Stop Loss (en dessous)
    
    // Commentaire pour identification
    request.comment = "Gold Long EA v2";
    
    Print("═══════════════════════════════════════════════════════");
    Print("🚀 ENVOI DE L'ORDRE LONG 🚀");
    Print("   Symbole    : ", request.symbol);
    Print("   Type       : BUY (LONG)");
    Print("   Volume     : ", request.volume, " lots");
    Print("   Prix entrée: ", request.price);
    Print("   Take Profit: ", request.tp);
    Print("   Stop Loss  : ", request.sl);
    Print("   Slippage   : ", request.deviation, " points");
    Print("═══════════════════════════════════════════════════════");
    
    // Envoyer l'ordre
    bool envoye = OrderSend(request, result);
    
    if(envoye)
    {
        Print("✅✅✅ TRADE LONG OUVERT AVEC SUCCÈS ! ✅✅✅");
        Print("   Ticket      : ", result.order);
        Print("   Prix entrée : ", result.price);
        Print("   Volume      : ", result.volume, " lots");
        Print("   Take Profit : ", tp);
        Print("   Stop Loss   : ", sl_final);
        Print("   Heure       : ", TimeToString(TimeCurrent()));
        
        // Alerte supplémentaire pour confirmation trade
        Alert("🔔 Trade LONG ouvert sur ", _Symbol, " @ ", DoubleToString(result.price, _Digits));
        PlaySound("alert.wav");
    }
    else
    {
        Print("❌❌❌ ERREUR OUVERTURE TRADE LONG ❌❌❌");
        Print("   Code erreur : ", result.retcode);
        Print("   Description : ", GetErrorDescription(result.retcode));
    }
}

//+------------------------------------------------------------------+
//| Compter les trades ouverts (positions)                          |
//+------------------------------------------------------------------+
int CountTrades()
{
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Obtenir la description d'une erreur                              |
//+------------------------------------------------------------------+
string GetErrorDescription(int code_erreur)
{
    switch(code_erreur)
    {
        case 10004: return "Requête invalide";
        case 10006: return "Volume incorrect";
        case 10007: return "Prix incorrect";
        case 10008: return "Slippage trop élevé";
        case 10009: return "Marge insuffisante";
        case 10010: return "Marché fermé";
        case 10011: return "Trade désactivé";
        case 10012: return "Délai d'attente dépassé";
        case 10013: return "Connexion perdue";
        case 10014: return "Ordre déjà en cours";
        default: return "Erreur inconnue (code: " + IntegerToString(code_erreur) + ")";
    }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                 IchimokuScript005_KumoBreak.mq5|
//|                          Copyright 2023, Invest Data Systems FR. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#property copyright "Copyright 2023, Invest Data Systems France."
#property link      "https://www.mql5.com"
#property version   "1.03"

#include <Trade\Trade.mqh> // Inclusion de la bibliothèque pour les opérations de trading

double bid, ask;

input bool enableTrading = true; // Option pour activer ou désactiver le trading

CTrade trade;
MqlRates mql_rates[]; // Tableau pour stocker les données de marché
double tenkan_sen_buffer[];
double kijun_sen_buffer[];
double senkou_span_a_buffer[];
double senkou_span_b_buffer[];
double chikou_span_buffer[];

//+------------------------------------------------------------------+
//| Fonction principale exécutée par le script                      |
//+------------------------------------------------------------------+
void OnStart()
{
    printf("Début des traitements Ichimoku");

    // Configure les tableaux comme séries
    ArraySetAsSeries(mql_rates, true);
    ArraySetAsSeries(tenkan_sen_buffer, true);
    ArraySetAsSeries(kijun_sen_buffer, true);
    ArraySetAsSeries(senkou_span_a_buffer, true);
    ArraySetAsSeries(senkou_span_b_buffer, true);
    ArraySetAsSeries(chikou_span_buffer, true);

    bool onlySymbolsInMarketwatch = true;
    int stotal = SymbolsTotal(onlySymbolsInMarketwatch); // Seulement les symboles du MarketWatch

    // Boucle sur tous les symboles pour exécuter la logique Ichimoku
    for (int sindex = 0; sindex < stotal; sindex++)
    {
        string sname = SymbolName(sindex, onlySymbolsInMarketwatch);
        if (sname != "")
        {
            Ichimoku(sname);
        }
    }

    printf("Fin des traitements Ichimoku");
}

//+------------------------------------------------------------------+
//| Fonction d'analyse Ichimoku pour un symbole donné               |
//+------------------------------------------------------------------+
void Ichimoku(string sname)
{
    // Vérifier si le trading est activé
    if (!enableTrading)
    {
        printf("Trading désactivé pour " + sname);
        return;
    }

    // Récupération des données de marché
    if (CopyRates(sname, PERIOD_CURRENT, 0, 64, mql_rates) <= 0)
    {
        printf("Erreur lors de la copie des données pour " + sname + ". Erreur: " + GetLastError());
        return;
    }

    bid = SymbolInfoDouble(sname, SYMBOL_BID);
    ask = SymbolInfoDouble(sname, SYMBOL_ASK);
    
    // Récupération du prix actuel (dernier prix)
    double current_price = (bid + ask) / 2; // Prix moyen ou utiliser bid/ask selon le sens
    double current_bid = bid;
    double current_ask = ask;

    // Paramètres Ichimoku
    int tenkan_sen = 9;
    int kijun_sen = 26;
    int senkou_span_b = 52;

    int max = 64;
    int handle = iIchimoku(sname, PERIOD_CURRENT, tenkan_sen, kijun_sen, senkou_span_b);
    if (handle == INVALID_HANDLE)
    {
        printf("Impossible de créer l'indicateur Ichimoku pour " + sname + ". Erreur: " + GetLastError());
        return;
    }

    // Copie des valeurs des buffers Ichimoku
    if (CopyBuffer(handle, TENKANSEN_LINE, 0, max, tenkan_sen_buffer) <= 0 ||
        CopyBuffer(handle, KIJUNSEN_LINE, 0, max, kijun_sen_buffer) <= 0 ||
        CopyBuffer(handle, SENKOUSPANA_LINE, 0, max, senkou_span_a_buffer) <= 0 ||
        CopyBuffer(handle, SENKOUSPANB_LINE, 0, max, senkou_span_b_buffer) <= 0 ||
        CopyBuffer(handle, CHIKOUSPAN_LINE, 0, max, chikou_span_buffer) <= 0)
    {
        printf("Erreur lors de la copie des buffers pour " + sname + ". Erreur: " + GetLastError());
        return;
    }

    // Index pour bougie n-1 (bougie précédente complétée)
    int index_n1 = 1;
    
    // Index pour bougie n-2 (avant-dernière bougie complétée)
    int index_n2 = 2;

    // Vérification des tailles avant d'accéder aux données
    if (ArraySize(mql_rates) <= index_n1 ||
        ArraySize(senkou_span_a_buffer) <= index_n1 ||
        ArraySize(senkou_span_b_buffer) <= index_n1)
    {
        printf("Index hors limite détecté pour " + sname);
        return;
    }

    // ==================== DETECTION SUR BOUGIE N-1 ====================
    
    // Signal ACHAT sur bougie n-1 avec filtrage
    bool buy_signal_n1 = false;
    
    if ((senkou_span_a_buffer[index_n1] < senkou_span_b_buffer[index_n1] &&
         mql_rates[index_n1].open < senkou_span_b_buffer[index_n1] &&
         mql_rates[index_n1].close > senkou_span_b_buffer[index_n1]) ||
        (senkou_span_a_buffer[index_n1] > senkou_span_b_buffer[index_n1] &&
         mql_rates[index_n1].open < senkou_span_a_buffer[index_n1] &&
         mql_rates[index_n1].close > senkou_span_a_buffer[index_n1]))
    {
        // Filtrage: prix actuel (ask pour achat) >= plus haut de la bougie concernée
        double high_of_candle = mql_rates[index_n1].high;
        
        if(current_ask >= high_of_candle)
        {
            buy_signal_n1 = true;
            printf("BUY SIGNAL VALIDATED FOR " + sname + " | Prix actuel: " + current_ask + " >= Plus haut bougie n-1: " + high_of_candle + " (bougie n-1)");
            // trade.Buy(0.5, sname, ask, 0, 0, "Signal d'achat Ichimoku");
        }
        else
        {
            printf("BUY SIGNAL DETECTED BUT NOT VALIDATED FOR " + sname + " | Prix actuel: " + current_ask + " < Plus haut bougie n-1: " + high_of_candle + " (en attente de dépassement)");
        }
    }
    
    // Signal VENTE sur bougie n-1 avec filtrage
    bool sell_signal_n1 = false;
    
    if ((senkou_span_a_buffer[index_n1] < senkou_span_b_buffer[index_n1] &&
         mql_rates[index_n1].open > senkou_span_a_buffer[index_n1] &&
         mql_rates[index_n1].close < senkou_span_a_buffer[index_n1]) ||
        (senkou_span_a_buffer[index_n1] > senkou_span_b_buffer[index_n1] &&
         mql_rates[index_n1].open > senkou_span_b_buffer[index_n1] &&
         mql_rates[index_n1].close < senkou_span_b_buffer[index_n1]))
    {
        // Filtrage: prix actuel (bid pour vente) <= plus bas de la bougie concernée
        double low_of_candle = mql_rates[index_n1].low;
        
        if(current_bid <= low_of_candle)
        {
            sell_signal_n1 = true;
            printf("SELL SIGNAL VALIDATED FOR " + sname + " | Prix actuel: " + current_bid + " <= Plus bas bougie n-1: " + low_of_candle + " (bougie n-1)");
            // trade.Sell(0.5, sname, bid, 0, 0, "Signal de vente Ichimoku");
        }
        else
        {
            printf("SELL SIGNAL DETECTED BUT NOT VALIDATED FOR " + sname + " | Prix actuel: " + current_bid + " > Plus bas bougie n-1: " + low_of_candle + " (en attente de cassure)");
        }
    }

    // ==================== DETECTION SUR BOUGIE N-2 ====================
    
    // Signal ACHAT sur bougie n-2 avec filtrage
    bool buy_signal_n2 = false;
    
    if ((senkou_span_a_buffer[index_n2] < senkou_span_b_buffer[index_n2] &&
         mql_rates[index_n2].open < senkou_span_b_buffer[index_n2] &&
         mql_rates[index_n2].close > senkou_span_b_buffer[index_n2]) ||
        (senkou_span_a_buffer[index_n2] > senkou_span_b_buffer[index_n2] &&
         mql_rates[index_n2].open < senkou_span_a_buffer[index_n2] &&
         mql_rates[index_n2].close > senkou_span_a_buffer[index_n2]))
    {
        // Filtrage: prix actuel (ask pour achat) >= plus haut de la bougie concernée
        double high_of_candle = mql_rates[index_n2].high;
        
        if(current_ask >= high_of_candle)
        {
            buy_signal_n2 = true;
            printf("BUY SIGNAL VALIDATED FOR " + sname + " | Prix actuel: " + current_ask + " >= Plus haut bougie n-2: " + high_of_candle + " (bougie n-2)");
            // trade.Buy(0.5, sname, ask, 0, 0, "Signal d'achat Ichimoku");
        }
        else
        {
            printf("BUY SIGNAL DETECTED BUT NOT VALIDATED FOR " + sname + " | Prix actuel: " + current_ask + " < Plus haut bougie n-2: " + high_of_candle + " (en attente de dépassement)");
        }
    }
    
    // Signal VENTE sur bougie n-2 avec filtrage
    bool sell_signal_n2 = false;
    
    if ((senkou_span_a_buffer[index_n2] < senkou_span_b_buffer[index_n2] &&
         mql_rates[index_n2].open > senkou_span_a_buffer[index_n2] &&
         mql_rates[index_n2].close < senkou_span_a_buffer[index_n2]) ||
        (senkou_span_a_buffer[index_n2] > senkou_span_b_buffer[index_n2] &&
         mql_rates[index_n2].open > senkou_span_b_buffer[index_n2] &&
         mql_rates[index_n2].close < senkou_span_b_buffer[index_n2]))
    {
        // Filtrage: prix actuel (bid pour vente) <= plus bas de la bougie concernée
        double low_of_candle = mql_rates[index_n2].low;
        
        if(current_bid <= low_of_candle)
        {
            sell_signal_n2 = true;
            printf("SELL SIGNAL VALIDATED FOR " + sname + " | Prix actuel: " + current_bid + " <= Plus bas bougie n-2: " + low_of_candle + " (bougie n-2)");
            // trade.Sell(0.5, sname, bid, 0, 0, "Signal de vente Ichimoku");
        }
        else
        {
            printf("SELL SIGNAL DETECTED BUT NOT VALIDATED FOR " + sname + " | Prix actuel: " + current_bid + " > Plus bas bougie n-2: " + low_of_candle + " (en attente de cassure)");
        }
    }

    // Libération des buffers pour éviter les fuites mémoire
    ArrayFree(senkou_span_b_buffer);
    ArrayFree(senkou_span_a_buffer);
    ArrayFree(tenkan_sen_buffer);
    ArrayFree(kijun_sen_buffer);
    ArrayFree(chikou_span_buffer);
    ArrayFree(mql_rates);
}

//+------------------------------------------------------------------+
//|                                            Export_Prices_All.mq5 |
//|                                    Exporte tous les prix Bid/Ask |
//+------------------------------------------------------------------+
#property script_show_inputs

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input string   FileName = "Market_Prices.txt";   // Nom du fichier
input bool     AppendTimestamp = true;           // Ajouter horodatage
input bool     IncludeMarketWatch = true;        // Inclure tous les symboles du Market Watch
input string   CustomSymbols = "";               // Symboles personnalisés (séparés par des virgules)
input bool     ShowOnlyEnabled = true;           // Afficher uniquement les symboles visibles dans Market Watch

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    string file_name = FileName;
    
    // Ajout de l'horodatage si demandé
    if(AppendTimestamp)
    {
        datetime now = TimeCurrent();
        string timestamp = TimeToString(now, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
        StringReplace(timestamp, ":", ".");
        StringReplace(timestamp, " ", "_");
        file_name = StringSubstr(FileName, 0, StringFind(FileName, ".txt")) + "_" + timestamp + ".txt";
    }
    
    // Ouverture du fichier en écriture
    int handle = FileOpen(file_name, FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        Print("Erreur: Impossible de créer le fichier ", file_name, ". Erreur: ", GetLastError());
        return;
    }
    
    // En-tête
    FileWrite(handle, "=== EXPORT DES PRIX BID/ASK ===");
    FileWrite(handle, "Date/Heure: " + TimeToString(TimeCurrent()));
    FileWrite(handle, "Format: Symbole | Bid | Ask | Spread (pips)");
    FileWrite(handle, "--------------------------------------------------");
    
    int exported = 0;
    
    // 1. Récupérer les symboles du Market Watch
    if(IncludeMarketWatch)
    {
        int total_symbols = SymbolsTotal(ShowOnlyEnabled);
        
        if(total_symbols == 0)
        {
            FileWrite(handle, "Aucun symbole trouvé dans le Market Watch.");
        }
        else
        {
            for(int i = 0; i < total_symbols; i++)
            {
                string symbol = SymbolName(i, ShowOnlyEnabled);
                if(ExportSymbolPrice(handle, symbol))
                    exported++;
            }
        }
    }
    
    // 2. Récupérer les symboles personnalisés
    if(CustomSymbols != "")
    {
        string custom_array[];
        int num_custom = SplitString(CustomSymbols, ',', custom_array);
        
        for(int i = 0; i < num_custom; i++)
        {
            string symbol = custom_array[i];
            StringTrimLeft(symbol);
            StringTrimRight(symbol);
            
            if(symbol != "")
            {
                // Vérifier si le symbole existe, sinon l'ajouter au Market Watch
                if(SymbolSelect(symbol, true) == false)
                {
                    FileWrite(handle, "ERREUR: " + symbol + " - Symbole non trouvé");
                }
                else
                {
                    if(ExportSymbolPrice(handle, symbol))
                        exported++;
                }
            }
        }
    }
    
    // Pied de page
    FileWrite(handle, "--------------------------------------------------");
    FileWrite(handle, "Total symboles exportés: " + IntegerToString(exported));
    FileWrite(handle, "Fin de l'export");
    
    FileClose(handle);
    
    Print("Export terminé. Fichier: ", file_name);
    Print("Symboles exportés: ", exported);
    
    // Ouvrir le dossier du terminal
    string terminal_path = TerminalInfoString(TERMINAL_DATA_PATH);
    Print("Dossier du terminal: ", terminal_path);
    Print("Fichier complet: ", terminal_path, "\\MQL5\\Files\\", file_name);
}

//+------------------------------------------------------------------+
//| Exporte le prix d'un symbole                                     |
//+------------------------------------------------------------------+
bool ExportSymbolPrice(int handle, string symbol)
{
    // Vérifier si le symbole est sélectionné dans le Market Watch
    if(SymbolSelect(symbol, true) == false)
    {
        FileWrite(handle, "ERREUR: " + symbol + " - Symbole non trouvé");
        return false;
    }
    
    // Forcer le rafraîchissement des prix
    SymbolInfoDouble(symbol, SYMBOL_BID);
    SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    // Récupérer les prix
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    if(bid == 0 || ask == 0)
    {
        FileWrite(handle, "ERREUR: " + symbol + " - Prix indisponible (bid=" + DoubleToString(bid, _Digits) + ", ask=" + DoubleToString(ask, _Digits) + ")");
        return false;
    }
    
    // Calcul du spread en pips
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double spread_pips = 0;
    if(point > 0)
        spread_pips = (ask - bid) / point;
    
    // Obtenir le nombre de décimales
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // Écrire dans le fichier
    string line = StringFormat("%-20s | Bid: %-12s | Ask: %-12s | Spread: %.1f pips",
                               symbol,
                               DoubleToString(bid, digits),
                               DoubleToString(ask, digits),
                               spread_pips);
    
    FileWrite(handle, line);
    return true;
}

//+------------------------------------------------------------------+
//| Fonction SplitString personnalisée                               |
//+------------------------------------------------------------------+
int SplitString(string str, ushort separator, string &result[])
{
    int count = 0;
    int start = 0;
    int pos = 0;
    
    // Convertir l'ushort en string pour la recherche
    string sep_str = CharToString((uchar)separator);
    
    while((pos = StringFind(str, sep_str, start)) != -1)
    {
        ArrayResize(result, count + 1);
        result[count] = StringSubstr(str, start, pos - start);
        count++;
        start = pos + 1;
    }
    
    if(start < StringLen(str))
    {
        ArrayResize(result, count + 1);
        result[count] = StringSubstr(str, start);
        count++;
    }
    
    return count;
}
//+------------------------------------------------------------------+

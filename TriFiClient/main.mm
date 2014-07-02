//
//  main.mm
//  wifi
//
//  Created by Kirkby, Brian on 6/11/14.
//  Copyright (c) 2014 Kirkby, Brian. All rights reserved.
//

#include <map>
#include <string>
#include <vector>
#include <sstream>
#include <iostream>
#import <CoreWLAN/CoreWLAN.h>

using namespace std;

bool APP_DEBUG = false;

static map<int,int> freqMap2400 = {{1,2412},{2,2417},{3,2422},{4,2427},{5,2432},{6,2437},{7,2442},
    {8,2447},{9,2452},{10,2457},{11,2462},{12,2467},{13,2472},{14,2482}};
static map<int,int> freqMap5000 = {{183,4915},{184,4920},{185,4925},{187,4935},{188,4940},{189,4945},
    {192,4960},{196,4980},{7,5035},{8,5040},{9,5045},{11,5055},{12,5060},{16,5080},{34,5170},
    {36,5180},{38,5190},{40,5200},{42,5210},{44,5220},{46,5230},{48,5240},{52,5260},{56,5280},
    {60,5300},{64,5320},{100,5500},{104,5520},{108,5540},{112,5560},{116,5580},{120,5600},
    {124,5620},{128,5640},{132,5660},{136,5680},{140,5700},{149,5745},{153,5765},{157,5785},
    {161,5805},{165,5825}};

struct AccessPoint
{
    string ssid;
    string bssid;
    int rssi;
    int channelBand;
    int channelNum;
    long channelWidth;
    int noise;
    bool operator<(const AccessPoint &ap) const { return rssi < ap.rssi; }
};

struct TestObj
{
    string t;
    bool operator<(const TestObj &o) const { return t < o.t; }
};

std::vector<std::string> &split(const std::string &s, char delim, std::vector<std::string> &elems) {
    std::stringstream ss(s);
    std::string item;
    while (std::getline(ss, item, delim)) {
        elems.push_back(item);
    }
    return elems;
}


std::vector<std::string> split(const std::string &s, char delim) {
    std::vector<std::string> elems;
    split(s, delim, elems);
    return elems;
}

string launchAirportExec()
{
    string ret = "";
    
    NSTask *task;
    
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport"];
    
    NSArray *arguments;
    arguments = [NSArray arrayWithObjects: @"-s", nil];
    [task setArguments: arguments];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data;
    data = [file readDataToEndOfFile];
    
    NSString *output;
    output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    
    return [output UTF8String];
}

//NOTE: this is a bit of a hack. the scanForNetworksWithSSID call in ScanAir()
//will cache the results for ~30 seconds. this means that subsequent calls will
//just return the same results. this means we are at the mercy of a single WIFI
//scan to try and find our signal strength which is problematic because WIFI scans
//are notoriously unreliable for single scans.
//this method uses the "/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -s"
//commandline tool to get x more strength scans for the networks used by
//scanForNetworksWithSSID and averages them
void normalizeSignals( vector<AccessPoint> &aps)
{
    static const int bssidLen = 17;
    static const int rssiLen = 4;
    static const int timesToRunExec = 3;
    map<string,vector<int>> signals;
    
    //run airport x times
    for(int i=0; i<timesToRunExec; i++)
    {
        string output = launchAirportExec();
    
        //now parse the output to get the signal strengths
        vector<string> lines = split(output,'\n');
        int bssidIdx = (int)lines.front().find("BSSID");
        int rssiIdx = (int)lines.front().find("RSSI");
    
        for( vector<string>::iterator itr = lines.begin()+1; itr != lines.end(); itr++) {
            string bssid = itr->substr( bssidIdx, bssidLen);
            int rssi;
            istringstream(itr->substr( rssiIdx, rssiLen)) >> rssi;
            if(signals.find(bssid) == signals.end())
            {
                signals[bssid] = vector<int>();
            }
            signals[bssid].push_back(rssi);
        }
    }
    
    //average out the signal and update in aps
    for( vector<AccessPoint>::iterator itr=aps.begin(); itr != aps.end(); itr++)
    {
        if( signals.find(itr->bssid) != signals.end())
        {
            int totalRssiVal = 0;
            int idxRssi = 0;
            for( vector<int>::iterator itrRssi=signals[itr->bssid].begin(); itrRssi != signals[itr->bssid].end(); itrRssi++)
            {
                //cout << totalRssiVal << endl;
                totalRssiVal += *itrRssi;
                idxRssi++;
            }
            //cout << totalRssiVal << ":" << idxRssi << endl;
            itr->rssi = (int)((int)totalRssiVal/(int)idxRssi);
        }
    }
}

vector<AccessPoint> ScanAir(const string& interfaceName)
{
    NSString* ifName = [NSString stringWithUTF8String:interfaceName.c_str()];
    CWInterface* interface = [CWInterface interfaceWithName:ifName];
    
    NSError* error = nil;
    NSArray* scanResult = [[interface scanForNetworksWithSSID:nil error:&error] allObjects];
    if (error)
    {
        NSLog(@"%@ (%ld)", [error localizedDescription], [error code]);
    }
    
    vector<AccessPoint> result;
    for (CWNetwork* network in scanResult)
    {
        AccessPoint ap;
        ap.ssid  = string([[network ssid] UTF8String]);
        ap.bssid = string([[network bssid] UTF8String]);
        ap.rssi = (int)[network rssiValue];
        ap.channelBand = (int)[[network wlanChannel] channelBand];
        ap.channelNum = (int)[[network wlanChannel] channelNumber];
        ap.channelWidth = [[network wlanChannel] channelWidth];
        ap.noise = (int)[network noiseMeasurement];
        result.push_back( ap);
    }
    sort(result.rbegin(), result.rend());
    
    return result;
}


void sendData( string json, string endPoint)
{
    // Create the request.
    NSString *urlstring = [NSString stringWithCString:endPoint.c_str()
                                                encoding:[NSString defaultCStringEncoding]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlstring]];
    
    //NSLog(@"%@", urlstring);
    
    // Specify that it will be a POST request
    request.HTTPMethod = @"POST";
    
    // This is how we set header fields
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    // Convert your data and set your request's HTTPBody property
    NSString *stringData = [NSString stringWithUTF8String:json.c_str()];
    NSData *requestBodyData = [stringData dataUsingEncoding:NSUTF8StringEncoding];
    request.HTTPBody = requestBodyData;
    
    // Create url connection and fire request
    NSURLResponse * response = nil;
    NSError * error = nil;
    //NSData * data = [NSURLConnection sendSynchronousRequest:request
    //don't really care about the reponse
    [NSURLConnection sendSynchronousRequest:request
                                          returningResponse:&response
                                                      error:&error];
    //NSString *myString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    //NSLog(@"%@", myString);
}

map<string,string> processParams( int argc, const char * argv[])
{
    map<string,string> results;
    for(int i=1; i<argc; i++){
        if(strncmp(argv[i],"-x", 2)==0){
            results["x"] = argv[++i];
        } else if(strncmp(argv[i],"-y", 2)==0){
            results["y"] = argv[++i];
        } else if(strncmp(argv[i],"-z", 2)==0){
            results["z"] = argv[++i];
        } else if(strncmp(argv[i],"-ep", 3)==0){
            results["ep"] = argv[++i];
        } else if( strncmp(argv[i],"-h", 2)==0) {
            printf( "usage: %s [-ep endpoint] [-d] [-h] [-z z] [-x x] [-y y]\n", argv[0]);
            exit(1);
        } else if(strncmp(argv[i],"-d", 2)==0) {
            APP_DEBUG = true;
        }
    }
    return results;
}

int lookupFreq(int channelBand, int channelNum)
{
    return channelBand==1?freqMap2400[channelNum]:freqMap5000[channelNum];
}

string buildRouterSigJson(string id, vector<AccessPoint> aps)
{
    string ret;
    ret = "{\"hostname\":\"";
    ret += id;
    ret += "\",\n\"routers\":{";
    for(vector<AccessPoint>::iterator itr = aps.begin(); itr!=aps.end(); itr++){
        string line="";
        if( itr != aps.begin()){
            line += ",";
        }
        line += "\n\"";
        line += itr->bssid;
        line += "\":{\"strength\":";
        line += to_string(itr->rssi);
        line += ",\"freq\":";
        int freq = lookupFreq(itr->channelBand, itr->channelNum);
        line += to_string(freq);
        line += ",\"noise\":";
        line += to_string(itr->noise);
        line += "}";
        if( APP_DEBUG) {
            //distance = 10 ^ ((27.55 - (20 * log10(frequency)) - signalLevel)/20)
            printf("%s : noise(%d) : distance(%2.2fm) : chanBand(%d) : chanNum(%d) : %s", line.c_str(), itr->noise,
                   pow( 10, (27.55f - (20.0f * log10(freq)) - itr->rssi)/20.0f),
                   itr->channelBand,
                   itr->channelNum,
                   itr->ssid.c_str());
        }
        ret += line;
    }
    ret += "}}\n";
    return ret;
}


int main(int argc, const char * argv[])
{

    char hostName[254];
    
    map<string,string> params = processParams( argc, argv);
    vector<AccessPoint> aps = ScanAir("en1");
    cout << "rssi:" << aps.front().rssi << endl;

    gethostname(hostName, 254);
    string routerSigJson = buildRouterSigJson(hostName,aps);
    string json;
    if( params["x"] != "" || params["y"] != "" || params["z"] != "") {
        if( params["x"] == "" || params["y"] == "" || params["z"]=="") {
            printf( "when using x, y or z you must have all three\n");
            exit(1);
        }
        json = "{\"location\":{\"floor\":";
        json += params["z"];
        json += ",\"x\":";
        json += params["x"];
        json += ",\"y\":";
        json += params["y"];
        json += "},\n\"routerSignature\":";
        json += routerSigJson;
        json += "}";
    } else {
        json = routerSigJson;
    }
    if( !APP_DEBUG) {
        printf("%s\n", json.c_str());
    } else {
        printf("\n");
    }
    if (params["ep"]!="") {
        printf("sending data to: %s\n", params["ep"].c_str());
        sendData(json, params["ep"]);
    }
    return 0;
}


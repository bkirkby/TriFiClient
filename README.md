tri-fi
===========
tri-fi is a machine learning indoor geolocation project. 

PROJECT
=======
this was a 3 day hack-a-thon where we started with the idea of creating an automatic map of where 
people sit in our 10 story company building. we initially decided to use trilateration of WIFI 
signals to get that data, but then realized that a machine learning algorithm (a regressional model 
like stochastic gradient decent) would provide many benefits over straight trilateration including:

    * self healing - when WIFI access points change, a machine learning algorithm will pick that up
    * crowd sourced training - with ML, we could get the users of the system to help train with 
    minimal annoyance
    * better accuracy - a regression algorithm will theoretically provide better results by using 
    the data from all APs within range (between 80-100 in our typical setting) rather than relying 
    on signals from three points.

TriFiClient
===========
this is a MacOSX client that creates what i call a "WIFI singature profile" which is a list of 
all the WIFI access points within range and converts them to distance. it then uploads that 
signature profile to a backend service that consults a trained machine learning regression model 
(currently using google's prediction API) to extrapolate the x, y and z coordinates and update a 
database.

# ---+ Extensions
# ---++ SoapPlugin

# **PERL_H**
# List of predefined services
$Foswiki::cfg{SoapPlugin}{Clients} = [
          {
            id => 'sap',
            uri => 'urn:...',
            proxy => 'http://sap.mycompany.com:50000/XISOAPAdapter/MessageServlet?channel=:foo:bar',
            xmlns => 'urn:sap-com:document:sap:rfc:functions',
            user => 'sap_user',
            password => 'sap_password',
          },
          {
            id => 'mockup',
            uri => 'urn:...',
            proxy => 'http://localhost:8088/mockFooBarBinding',
            xmlns => 'urn:sap-com:document:sap:rfc:functions',
          }
        ];

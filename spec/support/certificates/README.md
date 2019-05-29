# Ruby Driver Test TLS Certificates

## File Types

All files in this directory are in the PEM format.

The file extensions map to content as follows:

- `.key` - private key
- `.crt` - certificate
- `.pem` - certificate and private key combined in the same file

## Tools

To inspect a certificate:

    openssl x509 -text -in path.pem

Start a test server using the provided certificate:

    openssl s_server -port 29999 -cert server.pem

Use OpenSSL's test client to test certificate verification:

    openssl s_server -connect :29999 -cert client.pem

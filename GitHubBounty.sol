import "mortal.sol";
import "oraclizeAPI.sol";
import "stringUtils.sol";

contract GitHubBounty is usingOraclize, mortal {
    
    enum QueryType { IssueState, IssueAssignee, UserAddress }
    
    struct user {
        string login;
        address ethAddress;
    }
    
    struct issue {
        string url;
        uint prize;
        user assignee;
        string state;
        mapping (bytes32=>QueryType) queryType;
    }
 
    mapping (bytes32 => string) queries;
    mapping (string => issue) bounties;
    
    uint queriesDelay;

    function GitHubBounty() {
        queriesDelay = 60 * 60 * 24; // one day delay
    }
    
    function addIssueBounty(string issueUrl){
        if (msg.sender != owner) throw;
        if(bytes(issueUrl).length==0) throw;
        if(msg.value == 0) throw;
        
        bounties[issueUrl].url = issueUrl;
        bounties[issueUrl].prize = msg.value;
        bounties[issueUrl].state = "open";
 
        getIssueState(queriesDelay, issueUrl);
    }
     
    function getIssueState(uint delay, string issueUrl) internal {
        bytes32 myid = oraclize_query(delay, "URL", strConcat("json(",issueUrl,").state"),1000000);
        queries[myid] = issueUrl;
        bounties[issueUrl].queryType[myid] = QueryType.IssueState;
    }
    
    function getIssueAssignee(uint delay, string issueUrl) internal {
        bytes32 myid = oraclize_query(delay, "URL", strConcat("json(",issueUrl,").assignee.login"),1000000);
        queries[myid] = issueUrl;
        bounties[issueUrl].queryType[myid] = QueryType.IssueAssignee;
    }
    
    function getUserAddress(uint delay, string issueUrl, string login) internal {
        string memory url = strConcat("https://api.github.com/users/", login);
        bytes32 myid = oraclize_query(delay, "URL", strConcat("json(",url,").location"),1000000);
        queries[myid] = issueUrl;
        bounties[issueUrl].queryType[myid] = QueryType.UserAddress;
    }
    
    function sendBounty(string issueUrl) internal {
        if(bounties[issueUrl].prize > 0) {
            if (bounties[issueUrl].assignee.ethAddress.send(bounties[issueUrl].prize)) {
                bounties[issueUrl].prize = 0;
            }
        }
    }

    function __callback(bytes32 myid, string result) {
        if (msg.sender != oraclize_cbAddress()) throw;
 
        string issueUrl = queries[myid];
        QueryType queryType = bounties[issueUrl].queryType[myid];
        
        if(queryType == QueryType.IssueState) {
            if(StringUtils.equal(result, "closed")) {
                bounties[issueUrl].state = "closed";
                getIssueAssignee(0, issueUrl);
            }
            else{
                getIssueState(queriesDelay, issueUrl);
            }
        } 
        else if(queryType == QueryType.IssueAssignee) {
            if(bytes(result).length > 0) {
                bounties[issueUrl].assignee.login = result;
                getUserAddress(0, issueUrl, result);
            }
            else {
                getIssueAssignee(queriesDelay, issueUrl);
            }
        } 
        else if(queryType == QueryType.UserAddress) {
            if(bytes(result).length > 0) {
                bounties[issueUrl].assignee.ethAddress = parseAddr(result);
                sendBounty(issueUrl);
            }
            else {
                getUserAddress(queriesDelay, issueUrl, result);
            }
        } 
        
        delete bounties[issueUrl].queryType[myid];
        delete queries[myid];
    }
} 

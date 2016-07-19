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
        uint balance;
        user assignee;
        string state;
        mapping (bytes32=>QueryType) queryType;
    }
 
    mapping (bytes32 => string) queries;
    mapping (string => issue) bounties;
    
    uint queriesDelay = 60 * 60 * 24; // one day delay
    uint contractBalance;
    
    event BountyAdded(string issueUrl);
    event IssueStateLoaded(string issueUrl, string state);
    event IssueAssigneeLoaded(string issueUrl, string login);
    event UserAddressLoaded(string issueUrl, string ethAddress);
    event SendingBounty(string issueUrl, uint prize);
    event BountySent(string issueUrl);
    
    uint oraclizeGasLimit = 1000000;

    function GitHubBounty() {
    }
    
    function addIssueBounty(string issueUrl){
        BountyAdded(issueUrl);
        if (msg.sender != owner) throw;
        if(bytes(issueUrl).length==0) throw;
        if(msg.value == 0) throw;
        
        bounties[issueUrl].url = issueUrl;
        bounties[issueUrl].prize = msg.value;
        bounties[issueUrl].balance = msg.value;
        bounties[issueUrl].state = "open";
 
        getIssueState(queriesDelay, issueUrl);
    }
     
    function getIssueState(uint delay, string issueUrl) internal {
        contractBalance = this.balance;
        
        bytes32 myid = oraclize_query(delay, "URL", strConcat("json(",issueUrl,").closed_at"), oraclizeGasLimit);
        queries[myid] = issueUrl;
        bounties[issueUrl].queryType[myid] = QueryType.IssueState;
        
        bounties[issueUrl].balance -= contractBalance - this.balance;
    }
    
    function getIssueAssignee(uint delay, string issueUrl) internal {
        contractBalance = this.balance;
        
        bytes32 myid = oraclize_query(delay, "URL", strConcat("json(",issueUrl,").assignee.login"), oraclizeGasLimit);
        queries[myid] = issueUrl;
        bounties[issueUrl].queryType[myid] = QueryType.IssueAssignee;
        
        bounties[issueUrl].balance -= contractBalance - this.balance;
    }
    
    function getUserAddress(uint delay, string issueUrl, string login) internal {
        contractBalance = this.balance;
        
        string memory url = strConcat("https://api.github.com/users/", login);
        bytes32 myid = oraclize_query(delay, "URL", strConcat("json(",url,").location"), oraclizeGasLimit);
        queries[myid] = issueUrl;
        bounties[issueUrl].queryType[myid] = QueryType.UserAddress;
        
        bounties[issueUrl].balance -= contractBalance - this.balance;
    }
    
    function sendBounty(string issueUrl) internal {
        SendingBounty(issueUrl, bounties[issueUrl].balance);
        if(bounties[issueUrl].balance > 0) {
            if (bounties[issueUrl].assignee.ethAddress.send(bounties[issueUrl].balance)) {
                bounties[issueUrl].balance = 0;
                BountySent(issueUrl);
            }
        }
    }

    function __callback(bytes32 myid, string result) {
        if (msg.sender != oraclize_cbAddress()) throw;
 
        string issueUrl = queries[myid];
        QueryType queryType = bounties[issueUrl].queryType[myid];
        
        if(queryType == QueryType.IssueState) {
            IssueStateLoaded(issueUrl, result);
            if(bytes(result).length > 0) {
                bounties[issueUrl].state = "closed";
                getIssueAssignee(0, issueUrl);
            }
            else{
                getIssueState(queriesDelay, issueUrl);
            }
        } 
        else if(queryType == QueryType.IssueAssignee) {
            IssueAssigneeLoaded(issueUrl, result);
            if(bytes(result).length > 0) {
                bounties[issueUrl].assignee.login = result;
                getUserAddress(0, issueUrl, result);
            }
            else {
                getIssueAssignee(queriesDelay, issueUrl);
            }
        } 
        else if(queryType == QueryType.UserAddress) {
            UserAddressLoaded(issueUrl, result);
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
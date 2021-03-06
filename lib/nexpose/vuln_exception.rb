module Nexpose

  class Connection
    include XMLUtils

    # Retrieve vulnerability exceptions.
    #
    # @param [String] status Filter exceptions by the current status.
    #   @see Nexpose::VulnException::Status
    # @param [String] duration A time interval in the format "PnYnMnDTnHnMnS".
    # @return [Array[VulnException]] List of matching vulnerability exceptions.
    #
    def list_vuln_exceptions(status = nil, duration = nil)
      option = {}
      option['status'] = status if status
      option['time-duration'] = duration if duration
      xml = make_xml('VulnerabilityExceptionListingRequest', option)
      response = execute(xml, '1.2')

      xs = []
      if response.success
        response.res.elements.each('//VulnerabilityException') do |ve|
          xs << VulnException.parse(ve)
        end
      end
      xs
    end

    alias_method :vuln_exceptions, :list_vuln_exceptions

    # Resubmit a vulnerability exception request with a new comment and reason
    # after an exception has been rejected.
    #
    # You can only resubmit a request that has a "Rejected" status; if an
    # exception is "Approved" or "Under Review" you will receive an error
    # message stating that the exception request cannot be resubmitted.
    #
    # @param [Fixnum] id Unique identifier of the exception to resubmit.
    # @param [String] comment Comment to justify the exception resubmission.
    # @param [String] reason The reason for the exception status, if changing.
    #   @see Nexpose::VulnException::Reason
    # @return [Boolean] Whether or not the resubmission was valid.
    #
    def resubmit_vuln_exception(id, comment, reason = nil)
      options = { 'exception-id' => id }
      options['reason'] = reason if reason
      xml = make_xml('VulnerabilityExceptionResubmitRequest', options)
      comment_xml = make_xml('comment', {}, comment, false)
      xml.add_element(comment_xml)
      r = execute(xml, '1.2')
      r.success
    end

    # Recall a vulnerability exception. Recall is used by a submitter to undo an
    # exception request that has not been approved yet.
    #
    # You can only recall a vulnerability exception that has 'Under Review'
    # status.
    #
    # @param [Fixnum] id Unique identifier of the exception to resubmit.
    # @return [Boolean] Whether or not the recall was accepted by the console.
    #
    def recall_vuln_exception(id)
      xml = make_xml('VulnerabilityExceptionRecallRequest',
                     { 'exception-id' => id })
      execute(xml, '1.2').success
    end

    # Delete an existing vulnerability exception.
    #
    # @param [Fixnum] id The ID of a vuln exception.
    # @return [Boolean] Whether or not deletion was successful.
    #
    def delete_vuln_exception(id)
      xml = make_xml('VulnerabilityExceptionDeleteRequest',
                     { 'exception-id' => id })
      execute(xml, '1.2').success
    end
  end

  # A vulnerability exception.
  #
  # Certain attributes are necessary for some exception scopes, even though
  # they are optional otherwise.
  # • An exception for all instances of a vulnerability on all assets only
  #   requires the vuln_id attribute. The asset_id, vuln_key and port
  #   attributes are ignored for this scope type.
  # • An exception for all instances on a specific asset requires the vuln_id
  #   and asset_id attributes. The vuln_key and port attributes are ignored for
  #   this scope type.
  # • An exception for a specific instance of a vulnerability on a specific
  #   asset requires the vuln_id, asset_id. Additionally, the port and/or the
  #   key attribute must be specified.
  #
  class VulnException

    # Unique identifier assigned to an exception.
    attr_accessor :id
    # Unique identifier of a vulnerability.
    attr_accessor :vuln_id
    # The name of submitter of the exception.
    attr_accessor :submitter
    # The name of the reviewer of the exception.
    attr_accessor :reviewer
    # The state of the exception in the work flow process.
    # @see Nexpose::VulnException::Status
    attr_accessor :status
    # The reason for the exception status.
    # @see Nexpose::VulnException::Reason
    attr_accessor :reason
    # The scope of the exception.
    # @see Nexpose::VulnException::Scope
    attr_accessor :scope
    # ID of asset, if this exception applies to only one asset.
    attr_accessor :asset_id
    alias :device_id :asset_id
    alias :device_id= :asset_id=

    # Port on a asset, if this exception applies to a specific port.
    attr_accessor :port
    # The specific vulnerable component in a discovered instance of the
    # vulnerability referenced by the vuln_id, such as a program, file or user
    # account.
    attr_accessor :vuln_key
    # The date an exception will expire, causing the vulnerability to be
    # included in report risk scores.
    attr_accessor :expiration
    # Any comment provided by the submitter.
    attr_accessor :submitter_comment
    # Any comment provided by the reviewer.
    attr_accessor :reviewer_comment

    def initialize(vuln_id, scope, reason, status = nil)
      @vuln_id, @scope, @reason, @status = vuln_id, scope, reason, status
    end

    # Submit this exception on the security console.
    #
    # @param [Connection] connection Connection to security console.
    # @return [Fixnum] Newly assigned exception ID.
    #
    def save(connection, comment = nil)
      validate

      xml = connection.make_xml('VulnerabilityExceptionCreateRequest')
      xml.add_attributes({ 'vuln-id' => @vuln_id,
                           'scope' => @scope,
                           'reason' => @reason })
      case @scope
      when Scope::ALL_INSTANCES_ON_A_SPECIFIC_ASSET
        xml.add_attributes({ 'device-id' => @asset_id })
      when Scope::SPECIFIC_INSTANCE_OF_SPECIFIC_ASSET
        xml.add_attributes({ 'device-id' => @asset_id,
                             'port-no' => @port,
                             'vuln-key' => @vuln_key })
      end

      @submitter_comment = comment if comment
      if @submitter_comment
        comment_elem = REXML::Element.new('comment')
        comment_elem.add_text(@submitter_comment)
        xml.add_element(comment_elem)
      end

      response = connection.execute(xml, '1.2')
      @id = response.attributes['exception-id'].to_i if response.success
    end

    # Resubmit a vulnerability exception request with a new comment and reason
    # after an exception has been rejected.
    #
    # You can only resubmit a request that has a "Rejected" status; if an
    # exception is "Approved" or "Under Review" you will receive an error
    # message stating that the exception request cannot be resubmitted.
    #
    # This call will use the object's current state to resubmit.
    #
    # @param [Connection] connection Connection to security console.
    # @return [Boolean] Whether or not the resubmission was valid.
    #
    def resubmit(connection)
      raise ArgumentError.new('Only Rejected exceptions can be resubmitted.') unless @status == Status::REJECTED
      connection.resubmit_vuln_exception(@id, @submitter_comment, @reason)
    end

    # Recall a vulnerability exception. Recall is used by a submitter to undo an
    # exception request that has not been approved yet.
    #
    # You can only recall a vulnerability exception that has 'Under Review'
    # status.
    #
    # @param [Connection] connection Connection to security console.
    # @return [Boolean] Whether or not the recall was accepted by the console.
    #
    def recall(connection)
      connection.recall_vuln_exception(id)
    end

    # Approve a vulnerability exception request, update comments and expiration
    # dates on vulnerability exceptions that are "Under Review".
    #
    # @param [Connection] connection Connection to security console.
    # @param [String] comment Comment to accompany the approval.
    # @return [Boolean] Whether or not the approval was accepted by the console.
    #
    def approve(connection, comment = nil)
      xml = connection.make_xml('VulnerabilityExceptionApproveRequest',
                                { 'exception-id' => @id })
      if comment
        cxml = REXML::Element.new('comment')
        cxml.add_text(comment)
        xml.add_element(cxml)
        @reviewer_comment = comment
      end

      connection.execute(xml, '1.2').success
    end

    # Reject a vulnerability exception request and update comments for the
    # vulnerability exception request.
    #
    # @param [Connection] connection Connection to security console.
    # @param [String] comment Comment to accompany the rejection.
    # @return [Boolean] Whether or not the reject was accepted by the console.
    #
    def reject(connection, comment = nil)
      xml = connection.make_xml('VulnerabilityExceptionRejectRequest',
                                { 'exception-id' => @id })
      if comment
        cxml = REXML::Element.new('comment')
        cxml.add_text(comment)
        xml.add_element(cxml)
      end

      connection.execute(xml, '1.2').success
    end

    # Deletes this vulnerability exception.
    #
    # @param [Connection] connection Connection to security console.
    # @return [Boolean] Whether or not deletion was successful.
    #
    def delete(connection)
      connection.delete_vuln_exception(@id)
    end

    # Update security console with submitter comment on this vulnerability
    # exceptions.
    #
    # Cannot update a submit comment unless exception is under review or has
    # expired.
    #
    # @param [Connection] connection Connection to security console.
    # @param [String] comment Submitter comment on this exception.
    # @return [Boolean] Whether the comment was successfully submitted.
    #
    def update_submitter_comment(connection, comment)
      xml = connection.make_xml('VulnerabilityExceptionUpdateCommentRequest',
                                { 'exception-id' => @id })
      cxml = REXML::Element.new('submitter-comment')
      cxml.add_text(comment)
      xml.add_element(cxml)
      @submitter_comment = comment

      connection.execute(xml, '1.2').success
    end

    # Update security console with reviewer comment on this vulnerability
    # exceptions.
    #
    # @param [Connection] connection Connection to security console.
    # @param [String] comment Reviewer comment on this exception.
    # @return [Boolean] Whether the comment was successfully submitted.
    #
    def update_reviewer_comment(connection, comment)
      xml = connection.make_xml('VulnerabilityExceptionUpdateCommentRequest',
                                { 'exception-id' => @id })
      cxml = REXML::Element.new('reviewer-comment')
      cxml.add_text(comment)
      xml.add_element(cxml)
      @reviewer_comment = comment

      connection.execute(xml, '1.2').success
    end

    # Update the expiration date for this exception.
    # The expiration time cannot be in the past.
    #
    # @param [Connection] connection Connection to security console.
    # @param [String] new_date Date in the format "YYYY-MM-DD".
    # @return [Boolean] Whether the update was successfully submitted.
    #
    def update_expiration_date(connection, new_date)
      xml = connection.make_xml('VulnerabilityExceptionUpdateExpirationDateRequest',
                                { 'exception-id' => @id,
                                  'expiration-date' => new_date })
      connection.execute(xml, '1.2').success
    end

    # Validate that this exception meets to requires for the assigned scope.
    #
    def validate
      raise ArgumentError.new('No vuln_id.') unless @vuln_id
      raise ArgumentError.new('No scope.') unless @scope
      raise ArgumentError.new('No reason.') unless @reason

      case @scope
      when Scope::ALL_INSTANCES
        @asset_id = @port = @vuln_key = nil
      when Scope::ALL_INSTANCES_ON_A_SPECIFIC_ASSET
        raise ArgumentError.new('No asset_id.') unless @asset_id
        @port = @vuln_key = nil
      when Scope::SPECIFIC_INSTANCE_OF_SPECIFIC_ASSET
        raise ArgumentError.new('No asset_id.') unless @asset_id
        raise ArgumentError.new('Port or vuln_key is required.') unless @port || @vuln_key
      else
        raise ArgumentError.new("Invalid scope: #{@scope}")
      end
    end

    def self.parse(xml)
      exception = new(xml.attributes['vuln-id'],
                      xml.attributes['scope'],
                      xml.attributes['reason'],
                      xml.attributes['status'])

      exception.id = xml.attributes['exception-id']
      exception.submitter = xml.attributes['submitter']
      exception.reviewer = xml.attributes['reviewer']
      exception.asset_id = xml.attributes['device-id']
      exception.port = xml.attributes['port-no']
      exception.vuln_key = xml.attributes['vuln-key']
      # TODO: Convert to Date/Time object?
      exception.expiration = xml.attributes['expiration-date']

      submitter_comment = xml.elements['submitter-comment']
      exception.submitter_comment = submitter_comment.text if submitter_comment
      reviewer_comment = xml.elements['reviewer-comment']
      exception.reviewer_comment = reviewer_comment.text if reviewer_comment

      exception
    end

    # The state of a vulnerability exception in the work flow process.
    #
    module Status
      UNDER_REVIEW = 'Under Review'
      APPROVED = 'Approved'
      REJECTED = 'Rejected'
      DELETED = 'Deleted'
    end

    # The reason for the exception status.
    #
    module Reason
      FALSE_POSITIVE = 'False Positive'
      COMPENSATING_CONTROL = 'Compensating Control'
      ACCEPTABLE_USE = 'Acceptable Use'
      ACCEPTABLE_RISK = 'Acceptable Risk'
      OTHER = 'Other'
    end

    # The scope of the exception.
    #
    module Scope
      ALL_INSTANCES = 'All Instances'
      ALL_INSTANCES_ON_A_SPECIFIC_ASSET = 'All Instances on a Specific Asset'
      ALL_INSTANCES_IN_A_SPECIFIC_SITE = 'All Instances in a Specific Site'
      SPECIFIC_INSTANCE_OF_SPECIFIC_ASSET = 'Specific Instance of Specific Asset'
    end
  end
end

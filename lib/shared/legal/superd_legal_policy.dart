/// SuperD's Terms of Service & Privacy Policy - the single document a
/// vendor or driver agrees to before their signup form will submit (see
/// `PolicyScreen`, and the "I agree" checkbox on `VendorSignupScreen`/
/// `DriverSignupScreen`).
///
/// [kTermsVersion] is stored alongside the timestamp whenever someone
/// agrees (`vendors.terms_version`/`profiles.terms_version`, set by
/// `register_vendor()`/`handle_new_user()` - see
/// `0079_terms_acceptance.sql`) - bump it whenever [kPolicySections]
/// changes in any way that matters, so it's always possible to tell which
/// version of the text a given vendor/driver actually saw.
///
/// IMPORTANT: this text was drafted as a reasonable starting point for a
/// small Ghana-based courier platform, not by a lawyer. Anknovate IT
/// Services should have it reviewed by counsel qualified in Ghanaian law
/// (in particular against the Data Protection Act, 2012 (Act 843) and the
/// Electronic Transactions Act, 2008 (Act 772)) before treating it as a
/// binding, final agreement.
library;

const String kTermsVersion = '1.0';
const String kTermsEffectiveDate = '2 September 2026';
const String kOperatorLegalName = 'Anknovate IT Services';
const String kOperatorContactEmail = 'info@anknovate.com';

class PolicySection {
  const PolicySection(this.title, this.body);

  final String title;

  /// Paragraphs separated by a blank line; a line starting with "- " is
  /// rendered as a bullet within its paragraph.
  final String body;
}

const List<PolicySection> kPolicySections = [
  PolicySection(
    'Introduction and acceptance',
    'SuperD (the "Platform") is a delivery-coordination service operated '
        'by $kOperatorLegalName ("SuperD", "we", "us", or "our"), connecting '
        'businesses that need deliveries made ("Vendors") with independent '
        'delivery riders ("Drivers") through customers who place requests '
        '("Customers").\n\n'
        'This document is a single agreement covering both our Terms of '
        'Service and our Privacy Policy. By checking "I agree" on the '
        'Vendor or Driver signup form, you confirm that you have read, '
        'understood, and accept this document in full, and that you are '
        'entering into it on behalf of yourself or the business you '
        'represent. If you do not agree, do not check the box and do not '
        'use the Platform.\n\n'
        'This version took effect on $kTermsEffectiveDate and is '
        'identified internally as version $kTermsVersion.',
  ),
  PolicySection(
    'Who this applies to',
    '- A "Vendor" is a business that registers a public request link to '
        'receive delivery requests from its own customers.\n'
        '- A "Driver" is an individual who registers to accept and fulfil '
        'delivery requests routed to them through the Platform.\n'
        '- A "Customer" is a member of the public who places a delivery '
        'request through a Vendor\'s link. A Customer does not create an '
        'account and is not required to agree to this document, though the '
        'Privacy sections below still describe how their information is '
        'handled.\n\n'
        'Separate sections further down cover obligations specific to '
        'Vendors and specific to Drivers. The sections on privacy, data, '
        'liability, and governing law apply to everyone.',
  ),
  PolicySection(
    'Eligibility',
    'You must be at least 18 years old and legally capable of entering a '
        'binding agreement under the laws of Ghana to register as a Vendor '
        'or a Driver. A Driver must additionally hold a valid Ghanaian '
        'driving licence appropriate to their registered vehicle, and any '
        'insurance the law requires for that vehicle, both current and not '
        'expired.',
  ),
  PolicySection(
    'What information we collect',
    'To operate the Platform we collect:\n'
        '- Account information: full name, phone number, email address, '
        'and (for staff/Driver accounts) a password.\n'
        '- Vendor information: business name, business location, and the '
        'zone you operate in.\n'
        '- Driver information: date of birth, vehicle number and type, '
        'driving licence number and expiry, and vehicle insurance details.\n'
        '- Delivery information: pickup and drop-off addresses, package '
        'description, and the Customer\'s name and phone number for that '
        'delivery.\n'
        '- Location data: a Driver\'s live GPS location while online and '
        'on duty, used to route nearby delivery requests and to show a '
        'Customer or Vendor where their delivery is.\n'
        '- Proof of delivery: a photo and a one-time PIN confirming a '
        'Customer received their package.\n'
        '- Payment records: the amount and status of a Vendor\'s activation '
        'fee or a Driver\'s daily platform fee and commission - we record '
        'that a payment happened and its Mobile Money reference; we do not '
        'store your Mobile Money PIN or full account details.\n'
        '- Usage information such as when you signed in and which device '
        'notifications were sent to.',
  ),
  PolicySection(
    'Why we collect it',
    'We use this information only to operate the Platform: to match a '
        'delivery request with an available Driver, to let a Vendor and '
        'Customer track a delivery in progress, to verify a Driver is who '
        'they say they are and legally permitted to drive, to charge and '
        'record the fees described below, to send you SMS/email/push '
        'notifications about deliveries and your account, to investigate a '
        'complaint or incident, and to meet our own legal and accounting '
        'obligations.\n\n'
        'We do not sell your personal information, and we do not use it '
        'for advertising.',
  ),
  PolicySection(
    'Who we share it with',
    'We share information with the following third-party providers, only '
        'to the extent each needs it to do its job for us:\n'
        '- Hubtel - to send SMS notifications and (once configured) to '
        'process Mobile Money payments.\n'
        '- Resend - to send email notifications.\n'
        '- Paystack - to process Mobile Money payments (while active).\n'
        '- Google Maps - to show maps, look up addresses, and calculate '
        'delivery distances.\n'
        '- Firebase (Google) - to deliver push notifications to your '
        'device, where enabled.\n'
        '- Supabase - our database and application hosting provider, which '
        'stores all of the above on our behalf.\n\n'
        'We may also disclose information where required by Ghanaian law, '
        'a valid court order, or to protect the safety of a Customer, '
        'Driver, Vendor, or the public.',
  ),
  PolicySection(
    'How long we keep it',
    'We keep account and delivery records for as long as your account is '
        'active, and for a reasonable period afterward to meet accounting, '
        'tax, and dispute-resolution obligations. A Driver\'s live location '
        'is only ever current-position data used for routing - it is not '
        'kept as a continuous location history beyond what is needed to '
        'operate and audit deliveries.',
  ),
  PolicySection(
    'Your rights over your data',
    'Under the Data Protection Act, 2012 (Act 843) of Ghana, you have the '
        'right to know what personal data we hold about you, to request a '
        'copy of it, to ask us to correct it if it is inaccurate, and to '
        'ask us to delete it or stop processing it, subject to our own '
        'legal obligation to keep certain records (for example, completed '
        'delivery and payment history). To exercise any of these rights, '
        'contact us at $kOperatorContactEmail.',
  ),
  PolicySection(
    'Data security',
    'We restrict access to your data using database-level access rules, '
        'so a Vendor can only see their own orders and a Driver can only '
        'see deliveries assigned to them. All traffic between the app and '
        'our servers is encrypted (HTTPS). No system is completely '
        'immune to compromise, and we cannot guarantee absolute security, '
        'but we take reasonable, industry-standard measures to protect '
        'your information.',
  ),
  PolicySection(
    'Notifications',
    'By registering, you consent to receive SMS, email, and (where '
        'enabled) push notifications relating to your account and to '
        'deliveries you are involved in - these are operational messages, '
        'not marketing, and cannot be opted out of individually while '
        'keeping your account active, since they are how we tell you a '
        'delivery needs your attention.',
  ),
  PolicySection(
    'Vendor account and registration',
    'You may register as a Vendor either through the public self-service '
        'signup form or by being added directly by our staff. You are '
        'responsible for the accuracy of the business information you '
        'provide, and for anything a Customer submits through the delivery '
        'request link we issue you. Your public link is yours alone - do '
        'not share your private orders link with anyone, since it shows '
        'every order ever placed through your account.',
  ),
  PolicySection(
    'Vendor activation fee',
    'Where enabled, a self-registered Vendor account starts inactive until '
        'a one-time activation fee is paid by Mobile Money. The fee amount '
        'is set by us and may change for future registrations; it does '
        'not change retroactively for a fee you have already been charged. '
        'This fee is non-refundable once your account has been activated. '
        'A Vendor added directly by our staff is never charged this fee.',
  ),
  PolicySection(
    'What the Platform does and does not guarantee for Vendors',
    'We connect your delivery requests to available Drivers on a '
        'best-effort basis. We do not guarantee that a Driver will always '
        'be available, that a delivery will complete within any particular '
        'time, or that a Driver\'s conduct will meet any particular '
        'standard, though we investigate complaints and may deactivate a '
        'Driver who violates this agreement. We may suspend or deactivate '
        'a Vendor account that provides false information, is used for '
        'fraudulent or illegal orders, or otherwise breaches this '
        'agreement.',
  ),
  PolicySection(
    'Driver eligibility and verification',
    'You must provide accurate, current identity, licence, and insurance '
        'information, and keep it up to date, including notifying us '
        'before a licence or insurance policy on file expires. We may '
        'independently verify anything you submit, and may decline or '
        'revoke approval to drive on the Platform at our discretion, '
        'including for a failed or expired verification.',
  ),
  PolicySection(
    'Independent contractor status',
    'A Driver on SuperD is an independent contractor, not an employee, '
        'agent, or partner of $kOperatorLegalName. You choose whether to go '
        'online, which deliveries to accept, and how to carry them out, '
        'within the bounds of applicable law and this agreement. You are '
        'responsible for your own vehicle, fuel, taxes, and any '
        'employment-related obligations toward anyone you may engage to '
        'help you. Nothing in this agreement creates an employment '
        'relationship between you and $kOperatorLegalName.',
  ),
  PolicySection(
    'Driver conduct',
    'While on duty you must drive safely and lawfully, handle every '
        'package with reasonable care, treat Customers, Vendors, and other '
        'Platform users with respect, and accurately report any incident, '
        'delay, or reason you cannot complete a delivery. A delivery is '
        'only marked complete once the Customer\'s one-time PIN is entered '
        '- do not ask a Customer for their PIN before you have actually '
        'handed over their package.',
  ),
  PolicySection(
    'Location tracking while on duty',
    'By going online as a Driver, you consent to the Platform collecting '
        'your live location for as long as you remain online, so that '
        'nearby delivery requests can be routed to you and so a Customer '
        'or Vendor can see your progress on an active delivery. Location '
        'collection stops when you go offline.',
  ),
  PolicySection(
    'Daily platform fee and commission',
    'A Driver pays a daily platform fee, priced according to the tiers '
        'shown in the app, and owes a per-delivery commission on completed '
        'deliveries, both by Mobile Money. An unpaid fee or overdue '
        'commission may block new deliveries from being assigned to you '
        'until it is settled, as described in the app. Fee tiers and the '
        'commission rate may change; we will make any change visible in '
        'the app before it takes effect for new charges.',
  ),
  PolicySection(
    'Suspension and termination',
    'Either party may stop using the Platform at any time. We may suspend '
        'or deactivate a Vendor or Driver account, or "freeze" a Driver '
        'account from accepting new work, for a breach of this agreement, '
        'suspected fraud, a safety concern, non-payment of fees owed, or '
        'at our reasonable discretion, and will where practical explain '
        'why. Sections of this agreement that by their nature should '
        'survive termination (including payment obligations already '
        'incurred, data retention, and limitation of liability) continue '
        'to apply after your account is closed.',
  ),
  PolicySection(
    'Limitation of liability',
    'The Platform is provided on an "as is" and "as available" basis. To '
        'the fullest extent permitted by Ghanaian law, $kOperatorLegalName '
        'is not liable for indirect, incidental, or consequential loss '
        'arising from your use of the Platform, for the acts or omissions '
        'of a Vendor, Driver, or Customer (who are independent of us), or '
        'for a delivery delay or failure outside our reasonable control. '
        'Nothing in this section limits liability that cannot lawfully be '
        'limited or excluded.',
  ),
  PolicySection(
    'Changes to this agreement',
    'We may update this document from time to time, for example to '
        'reflect a new feature or a change in the law. A change that '
        'materially affects your rights or obligations will require you '
        'to accept the updated version - shown as a new version number and '
        'date at the top of this page - before you can continue using the '
        'relevant part of the Platform.',
  ),
  PolicySection(
    'Governing law and disputes',
    'This agreement is governed by the laws of the Republic of Ghana. Any '
        'dispute arising from it should first be raised with us at '
        '$kOperatorContactEmail so we can try to resolve it directly; '
        'failing that, the courts of Ghana have jurisdiction.',
  ),
  PolicySection(
    'Contact us',
    'For any question about this agreement, or to exercise a data-privacy '
        'right described above, contact $kOperatorLegalName at '
        '$kOperatorContactEmail.',
  ),
];
